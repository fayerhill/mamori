import Foundation
import Combine
import Security
import ServiceManagement
import MamoriCore

private final class GuardReply: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let continuation: CheckedContinuation<Data?, Never>
    let connection: NSXPCConnection
    init(_ continuation: CheckedContinuation<Data?, Never>, connection: NSXPCConnection) {
        self.continuation = continuation
        self.connection = connection
    }
    func finish(_ data: Data?) {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        lock.unlock()
        connection.invalidate()
        continuation.resume(returning: data)
    }
}

/// Does not install or activate anything at initialization. The user must invoke setup/start.
@MainActor public final class GuardClient: ObservableObject {
    @Published public private(set) var status = GuardStatus(phase: .unavailable, message: "Check network guard setup before starting protection.")
    private static let pendingKey = "MamoriGuardMayOwnNetworkState"
    private var mayOwnNetworkState = UserDefaults.standard.bool(forKey: pendingKey)
    public init() {}

    /// Persists across launches until the authenticated helper confirms restoration.
    public var requiresRestoration: Bool { mayOwnNetworkState }

    private func setPending(_ value: Bool) {
        mayOwnNetworkState = value
        UserDefaults.standard.set(value, forKey: Self.pendingKey)
    }
    private func unavailable(_ message: String) -> GuardStatus {
        update(mayOwnNetworkState ? .fault : .unavailable,
               mayOwnNetworkState ? message + " A previous network guard session still requires verified restoration." : message)
    }

    public var canInstall: Bool { signingTeam() != nil && helperIsBundled }
    public var setupMessage: String {
        canInstall ? "Install Mamori's background service to enable network protection. macOS will ask for approval." : "This build has no usable Apple signing identity. Network protection requires a signed Mamori app and helper; keep-awake and VPN observation remain available."
    }

    @discardableResult public func check() async -> GuardStatus {
        guard let team = signingTeam(), helperIsBundled else { return unavailable(setupMessage) }
        switch SMAppService.daemon(plistName: GuardIdentity.plist).status {
        case .enabled: return await request(.status, team: team)
        case .requiresApproval: return unavailable("Approve Mamori in System Settings > General > Login Items & Extensions, then check again.")
        case .notRegistered, .notFound: return unavailable("Network guard is not installed. Install it before enabling protection.")
        @unknown default: return unavailable("The background service status is unknown.")
        }
    }

    @discardableResult public func install() async -> GuardStatus {
        guard canInstall else { return unavailable(setupMessage) }
        do { try SMAppService.daemon(plistName: GuardIdentity.plist).register() }
        catch { return unavailable("The background service could not be registered: \(error.localizedDescription)") }
        return await check()
    }

    public func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }

    @discardableResult public func start(configuration: GuardConfiguration) async -> GuardStatus {
        do { try GuardPolicy.validate(configuration) }
        catch { return update(.fault, error.localizedDescription) }
        guard let team = signingTeam(), helperIsBundled else { return unavailable(setupMessage) }
        guard SMAppService.daemon(plistName: GuardIdentity.plist).status == .enabled else { return await check() }
        setPending(true)
        status = GuardStatus(phase: .arming, message: "Verifying the network guard.", configuration: configuration, helperAvailable: true)
        return await request(.start(configuration), team: team)
    }

    /// A successful inactive reply is the acknowledgment required before a normal Quit.
    @discardableResult public func stop() async -> GuardStatus {
        guard let team = signingTeam(), helperIsBundled else {
            if mayOwnNetworkState {
                return update(.fault, "The guard could not be contacted. Network restoration has not been confirmed.")
            }
            return update(.inactive, "This build has not activated network protection.")
        }
        let service = SMAppService.daemon(plistName: GuardIdentity.plist)
        guard service.status == .enabled else {
            if mayOwnNetworkState {
                return update(.fault, "The background service is unavailable. Network restoration has not been confirmed.")
            }
            return update(.inactive, "The network guard has not been started.")
        }
        return await request(.stop, team: team)
    }

    @discardableResult public func uninstall() async -> GuardStatus {
        let service = SMAppService.daemon(plistName: GuardIdentity.plist)
        if service.status != .enabled && mayOwnNetworkState {
            return update(.fault, "An earlier network guard session requires restoration before uninstall. Restore helper access and retry.")
        }
        if service.status == .enabled {
            guard let team = signingTeam() else { return update(.fault, "A signed Mamori app is required to restore the installed guard before removal.") }
            let result = await request(.uninstall, team: team)
            guard result.phase == .inactive else { return result }
        }
        do {
            if service.status != .notRegistered && service.status != .notFound { try await service.unregister() }
            if SMAppService.mainApp.status == .enabled { try await SMAppService.mainApp.unregister() }
            return update(.inactive, "Mamori's network guard is stopped and its background services are unregistered.")
        } catch { return update(.fault, "Network rules were restored, but background-service removal did not complete: \(error.localizedDescription)") }
    }

    private enum Request { case status, start(GuardConfiguration), stop, uninstall }
    private func request(_ operation: Request, team: String) async -> GuardStatus {
        let connection = NSXPCConnection(machServiceName: GuardIdentity.service, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: GuardXPCProtocol.self)
        connection.setCodeSigningRequirement("anchor apple generic and identifier \"\(GuardIdentity.service)\" and certificate leaf[subject.OU] = \"\(team)\"")
        let data: Data? = await withCheckedContinuation { continuation in
            let reply = GuardReply(continuation, connection: connection)
            connection.interruptionHandler = { reply.finish(nil) }
            connection.invalidationHandler = { reply.finish(nil) }
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in reply.finish(nil) }) as? GuardXPCProtocol else { reply.finish(nil); return }
            let completion: @Sendable (Data) -> Void = { reply.finish($0) }
            switch operation {
            case .status: proxy.getStatus(reply: completion)
            case let .start(config):
                guard let encoded = try? JSONEncoder().encode(config) else { reply.finish(nil); return }
                proxy.start(configuration: encoded, reply: completion)
            case .stop: proxy.stop(reply: completion)
            case .uninstall: proxy.prepareUninstall(reply: completion)
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 40) { reply.finish(nil) }
        }
        guard let data, let result = try? JSONDecoder().decode(GuardStatus.self, from: data) else {
            setPending(true)
            return update(.fault, "The background service did not confirm this operation. Do not assume network protection or restoration succeeded.")
        }
        setPending(GuardPolicy.restorationRequired(previouslyPending: mayOwnNetworkState, confirmedPhase: result.phase))
        if result.phase == .unavailable && mayOwnNetworkState {
            return unavailable(result.message)
        }
        status = result
        return result
    }

    private var helperIsBundled: Bool {
        Bundle.main.bundleIdentifier == GuardIdentity.app &&
        FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchDaemons/\(GuardIdentity.plist)").path) &&
        FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/MamoriGuard").path)
    }
    private func signingTeam() -> String? {
        var code: SecCode?
        var info: CFDictionary?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple generic and identifier \"\(GuardIdentity.app)\"" as CFString, [], &requirement) == errSecSuccess,
              SecCodeCheckValidity(code, [], requirement) == errSecSuccess,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let team = (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else { return nil }
        return team
    }
    private func update(_ phase: GuardPhase, _ message: String) -> GuardStatus {
        status = GuardStatus(phase: phase, message: message, configuration: status.configuration, helperAvailable: false)
        return status
    }
}
