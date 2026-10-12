import AppKit
import Darwin
import Foundation

public struct ApplicationSnapshot: Identifiable, Hashable, Sendable {
    public let name: String
    public let bundleIdentifier: String
    public let bundleURL: URL
    public let processIdentifier: Int32
    public let launchDate: Date

    /// Selection follows the application; termination also checks the process identity.
    public var id: String { "\(bundleIdentifier)|\(bundleURL.path)" }
    public var isRunning: Bool { processIdentifier > 0 }

    public init(
        name: String,
        bundleIdentifier: String,
        bundleURL: URL,
        processIdentifier: Int32,
        launchDate: Date
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL.resolvingSymlinksInPath().standardizedFileURL
        self.processIdentifier = processIdentifier
        self.launchDate = launchDate
    }
}

public enum ApplicationQuitResult: String, Sendable {
    case requested
    case alreadyStopped
    case identityChanged
    case excluded
    case refused
}

/// Performs only immediate, explicitly requested actions. It owns no retry timers.
@MainActor
public final class ApplicationsService {
    private var installedCatalog: [ApplicationSnapshot] = []
    private var catalogReadAt: ContinuousClock.Instant?

    public init() {}

    /// Refreshes process identities on every call; directory discovery is cached for 30 seconds.
    public func installed(refresh: Bool = false) -> [ApplicationSnapshot] {
        let now = ContinuousClock.now
        let needsRefresh = catalogReadAt.map { $0.duration(to: now) >= .seconds(30) } ?? true
        if refresh || needsRefresh {
            installedCatalog = discoverInstalledApplications()
            catalogReadAt = now
        }
        var catalog = Dictionary(uniqueKeysWithValues: installedCatalog.map { ($0.bundleURL.path, $0) })
        for running in list() { catalog[running.bundleURL.path] = running }
        return catalog.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func list() -> [ApplicationSnapshot] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications.compactMap { application in
            guard let snapshot = snapshot(of: application),
                  !isExcluded(snapshot),
                  seen.insert(snapshot.id).inserted else { return nil }
            return snapshot
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func requestQuit(_ snapshot: ApplicationSnapshot) -> ApplicationQuitResult {
        act(on: snapshot, force: false)
    }

    public func forceQuit(_ snapshot: ApplicationSnapshot) -> ApplicationQuitResult {
        act(on: snapshot, force: true)
    }

    public func isRunning(_ snapshot: ApplicationSnapshot) -> Bool {
        guard snapshot.isRunning,
              let application = NSRunningApplication(processIdentifier: snapshot.processIdentifier),
              !application.isTerminated,
              let current = self.snapshot(of: application) else { return false }
        return sameProcess(current, snapshot)
    }

    private func act(on expected: ApplicationSnapshot, force: Bool) -> ApplicationQuitResult {
        guard !isExcluded(expected) else { return .excluded }
        guard expected.isRunning,
              let application = NSRunningApplication(processIdentifier: expected.processIdentifier),
              !application.isTerminated else { return .alreadyStopped }
        guard let current = snapshot(of: application), sameProcess(current, expected) else {
            return .identityChanged
        }
        guard !isExcluded(current) else { return .excluded }
        let sent = force ? application.forceTerminate() : application.terminate()
        return sent ? .requested : .refused
    }

    private func snapshot(of application: NSRunningApplication) -> ApplicationSnapshot? {
        guard !application.isTerminated,
              application.activationPolicy != .prohibited,
              application.processIdentifier > 1,
              belongsToCurrentUser(application.processIdentifier),
              let bundleIdentifier = application.bundleIdentifier,
              let bundleURL = application.bundleURL,
              let launchDate = application.launchDate else { return nil }
        return ApplicationSnapshot(
            name: application.localizedName ?? bundleURL.deletingPathExtension().lastPathComponent,
            bundleIdentifier: bundleIdentifier,
            bundleURL: bundleURL,
            processIdentifier: application.processIdentifier,
            launchDate: launchDate
        )
    }

    private func discoverInstalledApplications() -> [ApplicationSnapshot] {
        let manager = FileManager.default
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            manager.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]
        var found: [String: ApplicationSnapshot] = [:]
        for root in roots {
            guard let enumerator = manager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                let depth = url.pathComponents.count - root.pathComponents.count
                if url.pathExtension.lowercased() == "app" {
                    enumerator.skipDescendants()
                    let canonicalURL = url.resolvingSymlinksInPath().standardizedFileURL
                    guard found[canonicalURL.path] == nil,
                          let bundle = Bundle(url: canonicalURL),
                          bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
                          (bundle.object(forInfoDictionaryKey: "LSBackgroundOnly") as? NSNumber)?.boolValue != true,
                          let identifier = bundle.bundleIdentifier,
                          !identifier.isEmpty else { continue }
                    let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                        ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                        ?? canonicalURL.deletingPathExtension().lastPathComponent
                    let application = ApplicationSnapshot(
                        name: name,
                        bundleIdentifier: identifier,
                        bundleURL: canonicalURL,
                        processIdentifier: 0,
                        launchDate: .distantPast
                    )
                    if !isExcluded(application) { found[canonicalURL.path] = application }
                } else if depth >= 4 {
                    enumerator.skipDescendants()
                }
            }
        }
        return Array(found.values)
    }

    private func belongsToCurrentUser(_ pid: pid_t) -> Bool {
        var info = proc_bsdinfo()
        let length = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, length) == length else { return false }
        return info.pbi_uid == getuid()
    }

    private func sameProcess(_ current: ApplicationSnapshot, _ expected: ApplicationSnapshot) -> Bool {
        current.bundleIdentifier == expected.bundleIdentifier &&
        current.bundleURL == expected.bundleURL &&
        current.processIdentifier == expected.processIdentifier &&
        current.launchDate == expected.launchDate
    }

    private func isExcluded(_ application: ApplicationSnapshot) -> Bool {
        if application.processIdentifier == ProcessInfo.processInfo.processIdentifier { return true }
        let identifier = application.bundleIdentifier.lowercased()
        let protectedIdentifiers: Set<String> = [
            "com.apple.finder", "com.apple.dock", "com.apple.loginwindow",
            "com.apple.systemuiserver", "com.apple.controlcenter", "com.apple.windowmanager",
            "com.apple.securityagent", "com.apple.systempreferences", "com.mamori.app"
        ]
        if protectedIdentifiers.contains(identifier) { return true }
        if identifier == Bundle.main.bundleIdentifier?.lowercased() { return true }
        if identifier.hasPrefix("com.cloudflare.") { return true }
        let identity = "\(identifier) \(application.name)".lowercased()
        let protectedNames = [
            "mamori", "globalprotect", "paloaltonetworks", "pangps", "pangpa", "vpn",
            "wireguard", "tailscale", "tunnelblick", "viscosity", "mullvad",
            "anyconnect", "cisco secure", "forticlient", "cloudflare warp",
            "clash", "surge", "quantumult", "shadowrocket", "sing-box"
        ]
        return protectedNames.contains { identity.contains($0) }
    }
}
