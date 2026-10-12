import Foundation
import MamoriCore
import Security
import Darwin

private struct CommandResult {
    let code: Int32
    let output: String
    let error: String
}

private enum GuardFailure: Error, LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { value } else { "Guard operation failed." } }
}

/// All calls occur on the service's serial queue. No command strings are evaluated by a shell.
private enum Commands {
    static func run(_ executable: String, _ arguments: [String], input: String? = nil) throws -> CommandResult {
        let process = Process()
        let output = Pipe(), error = Pipe(), stdin = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = output
        process.standardError = error
        if input != nil { process.standardInput = stdin }
        try process.run()
        if let input {
            stdin.fileHandleForWriting.write(Data(input.utf8))
            try? stdin.fileHandleForWriting.close()
        }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 8, execute: timeout)
        let bytes = output.fileHandleForReading.readDataToEndOfFile()
        let errorBytes = error.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        return CommandResult(code: process.terminationStatus, output: String(decoding: bytes, as: UTF8.self), error: String(decoding: errorBytes, as: UTF8.self))
    }
    static func pf(_ arguments: [String], input: String? = nil) throws -> String {
        let result = try run("/sbin/pfctl", arguments, input: input)
        guard result.code == 0 else { throw GuardFailure.message("PF could not complete the requested operation (\(result.code)).") }
        return result.output
    }
}

private enum JournalStore {
    static let directory = URL(fileURLWithPath: "/Library/Application Support/Mamori", isDirectory: true)
    static let file = directory.appendingPathComponent("guard-session.json")
    static func ensureDirectory() throws {
        if mkdir(directory.path, 0o700) != 0 && errno != EEXIST { throw GuardFailure.message("The guard could not create its private recovery directory.") }
        var info = stat()
        guard lstat(directory.path, &info) == 0, info.st_uid == 0,
              info.st_mode & S_IFMT == S_IFDIR, info.st_mode & 0o022 == 0 else {
            throw GuardFailure.message("The guard recovery directory has unsafe ownership or permissions.")
        }
    }
    static func load() throws -> GuardJournal? {
        guard FileManager.default.fileExists(atPath: directory.path) else { return nil }
        try ensureDirectory()
        var info = stat()
        guard lstat(file.path, &info) == 0 else { if errno == ENOENT { return nil }; throw GuardFailure.message("The recovery journal cannot be inspected.") }
        guard info.st_uid == 0, info.st_mode & S_IFMT == S_IFREG, info.st_size < 131_072 else { throw GuardFailure.message("The recovery journal is not a safe regular file.") }
        return try JSONDecoder().decode(GuardJournal.self, from: Data(contentsOf: file))
    }
    static func save(_ journal: GuardJournal) throws {
        try ensureDirectory()
        try JSONEncoder().encode(journal).write(to: file, options: .atomic)
        guard chmod(file.path, 0o600) == 0 else { throw GuardFailure.message("The recovery journal permissions could not be set.") }
    }
    static func remove() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        // Remove only an empty directory, never recursively delete a caller-provided path.
        if rmdir(directory.path) != 0 && errno != ENOENT && errno != ENOTEMPTY { throw GuardFailure.message("The empty recovery directory could not be removed.") }
    }
}

private enum VPNVerification {
    static func connected(_ config: GuardConfiguration, requireEndpoints: Bool) -> Bool {
        guard let interfaces = try? Commands.run("/sbin/ifconfig", [config.tunnelInterface]), interfaces.code == 0,
              interfaces.output.contains("UP"), interfaces.output.contains("inet ") || interfaces.output.contains("inet6 ") else { return false }
        // Route queries do not send packets. Both halves of the IPv4 Internet must select the chosen tunnel.
        for destination in ["1.1.1.1", "208.67.222.222"] {
            guard let result = try? Commands.run("/sbin/route", ["-n", "get", destination]), result.code == 0,
                  result.output.split(separator: "\n").contains(where: { $0.trimmingCharacters(in: .whitespaces) == "interface: \(config.tunnelInterface)" }) else { return false }
        }
        guard let running = try? Commands.run("/usr/bin/pgrep", ["-x", "PanGPS"]), running.code == 0,
              let pid = running.output.split(separator: "\n").first,
              let path = try? Commands.run("/bin/ps", ["-p", String(pid), "-o", "comm="]),
              path.output.trimmingCharacters(in: .whitespacesAndNewlines) == "/Applications/GlobalProtect.app/Contents/Resources/PanGPS" else { return false }
        var code: SecStaticCode?
        let url = URL(fileURLWithPath: "/Applications/GlobalProtect.app/Contents/Resources/PanGPS")
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString("anchor apple generic and identifier \"PanGPS\" and certificate leaf[subject.OU] = \"PXPZ95SK77\"" as CFString, [], &requirement) == errSecSuccess,
              SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess else { return false }
        if requireEndpoints {
            guard let sockets = try? Commands.run("/usr/sbin/lsof", ["-nP", "-a", "-c", "PanGPS", "-i"]), sockets.code == 0 else { return false }
            let expression = try? NSRegularExpression(pattern: #"->([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+):(443|4501)(?:\s|$)"#)
            let text = sockets.output
            let matches = expression?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
            let observed = Set(matches.compactMap { match -> String? in
                guard let range = Range(match.range(at: 1), in: text) else { return nil }
                return String(text[range])
            })
            guard !observed.isEmpty, observed.isSubset(of: Set(config.gatewayAddresses)) else { return false }
        }
        return true
    }
}

final class GuardEngine: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.mamori.guard.state")
    private var journal: GuardJournal?
    private var status = GuardStatus(phase: .inactive, message: "Network protection is inactive.", helperAvailable: true)
    private var timer: DispatchSourceTimer?
    private var lastTunnelAllowed: Bool?

    init() {
        queue.async { [self] in
            do {
                journal = try JournalStore.load()
                if let journal {
                    status = GuardStatus(phase: .fault, message: "A previous guard session needs verification.", configuration: journal.configuration, helperAvailable: true)
                    if journal.desiredArmed { refresh() } else { restore() }
                }
            } catch { fault(error.localizedDescription) }
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 3, repeating: 3, leeway: .milliseconds(300))
            timer.setEventHandler { [weak self] in if self?.journal?.desiredArmed == true { self?.refresh() } }
            timer.resume()
            self.timer = timer
        }
    }

    func perform(_ action: String, configuration: Data? = nil, uid: uid_t, reply: @escaping @Sendable (Data) -> Void) {
        queue.async { [self] in
            if let owner = journal?.ownerUID, owner != uid { reply(encode(GuardStatus(phase: .fault, message: "This guard session belongs to another signed-in user.", helperAvailable: true))); return }
            switch action {
            case "start":
                if let configuration { arm(configuration, uid: uid) }
            case "stop", "uninstall": restore()
            default: if journal?.desiredArmed == true { refresh() }
            }
            reply(encode(status))
            if (action == "stop" || action == "uninstall") && status.phase == .inactive {
                queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                    // Demand-started launchd service: explicit successful Stop is a normal exit.
                    if self?.journal == nil { exit(0) }
                }
            }
        }
    }

    private func encode(_ value: GuardStatus) -> Data { (try? JSONEncoder().encode(value)) ?? Data() }
    private func fault(_ message: String) {
        status = GuardStatus(phase: .fault, message: message, configuration: journal?.configuration, helperAvailable: true)
    }
    private func pfState() throws -> (enabled: Bool, count: Int) {
        let info = try Commands.pf(["-s", "info"])
        guard let enabled = info.range(of: #"Status:\s+(Enabled|Disabled)"#, options: .regularExpression) else { throw GuardFailure.message("PF status could not be read.") }
        let states = try Commands.pf(["-s", "states"])
        return (info[enabled].contains("Enabled"), states.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }
    private func verifyNoSkipInterfaces() throws {
        let interfaces = try Commands.pf(["-v", "-s", "Interfaces"])
        guard !interfaces.lowercased().contains("skip") else {
            throw GuardFailure.message("PF has interface skip settings. Mamori cannot establish complete packet filtering.")
        }
    }
    private func ownRules() throws -> String { try Commands.pf(["-a", GuardIdentity.anchor, "-s", "rules"]) }

    private func arm(_ data: Data, uid: uid_t) {
        guard journal == nil else { fault("A guard session already exists. Restore it before starting another."); return }
        do {
            guard try JournalStore.load() == nil else { throw GuardFailure.message("A persisted guard session needs restoration before starting.") }
            guard data.count <= 8192 else { throw GuardFailure.message("The guard configuration is too large.") }
            let config = try JSONDecoder().decode(GuardConfiguration.self, from: data)
            try GuardPolicy.validate(config)
            guard VPNVerification.connected(config, requireEndpoints: true) else { throw GuardFailure.message("The selected tunnel and gateway could not be verified as the active GlobalProtect connection. Connect GlobalProtect first and confirm its gateway addresses.") }
            let pf = try pfState()
            try verifyNoSkipInterfaces()
            let root = try Commands.pf(["-s", "rules"])
            try GuardPolicy.preflight(rootRules: root, recursiveRules: Commands.pf(["-a", "*", "-s", "rules"]), pfEnabled: pf.enabled, stateCount: pf.count)
            guard try ownRules().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GuardFailure.message("Mamori's anchor is already occupied. Restore the previous session first.") }
            var record = GuardJournal(configuration: config, ownerUID: uid, rootRules: root)
            try JournalStore.save(record)
            journal = record
            status = GuardStatus(phase: .arming, message: "Preparing the network guard.", configuration: config, helperAvailable: true)
            let rules = try GuardPolicy.render(config, tunnelAllowed: true)
            _ = try Commands.pf(["-a", GuardIdentity.anchor, "-n", "-f", "-"], input: rules)
            _ = try Commands.pf(["-a", GuardIdentity.anchor, "-f", "-"], input: rules)
            record.expectedRules = try ownRules()
            guard record.expectedRules.contains("mamori-default-deny"), record.expectedRules.contains("mamori-tunnel") else { throw GuardFailure.message("The guard rules could not be verified after loading.") }
            try JournalStore.save(record)
            journal = record
            // Recheck after loading while PF is still disabled. Never flush another component's states.
            let beforeEnable = try pfState()
            guard !beforeEnable.enabled, beforeEnable.count == 0 else { throw GuardFailure.message("PF changed during setup. Protection was not activated.") }
            record.enableRequested = true
            try JournalStore.save(record)
            journal = record
            let result = try Commands.run("/sbin/pfctl", ["-E"])
            let combined = result.output + "\n" + result.error
            let expression = try NSRegularExpression(pattern: #"Token\s*:\s*([0-9]+)"#)
            guard result.code == 0, let match = expression.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)), let range = Range(match.range(at: 1), in: combined) else {
                throw GuardFailure.message("PF did not return a usable enable reference. The recovery journal was retained; protection cannot be verified.")
            }
            record.token = String(combined[range])
            journal = record
            try JournalStore.save(record)
            lastTunnelAllowed = true
            refresh()
        } catch { fault(error.localizedDescription) }
    }

    private func refresh() {
        guard var record = journal, record.desiredArmed else { return }
        do {
            let pf = try pfState()
            try verifyNoSkipInterfaces()
            guard pf.enabled, pf.count == 0,
                  try Commands.pf(["-s", "rules"]) == record.rootRules,
                  try ownRules() == record.expectedRules,
                  try GuardPolicy.containsOnlyOwnedFilterRules(Commands.pf(["-a", "*", "-s", "rules"]), expectedOwnRules: record.expectedRules),
                  GuardPolicy.mayResumeProtection(desiredArmed: record.desiredArmed, token: record.token, rulesMatch: true) else {
                throw GuardFailure.message("The firewall changed or could not be verified. Existing Mamori rules are retained; protection is not confirmed.")
            }
            let connected = VPNVerification.connected(record.configuration, requireEndpoints: false)
            if lastTunnelAllowed != connected {
                _ = try Commands.pf(["-a", GuardIdentity.anchor, "-f", "-"], input: GuardPolicy.render(record.configuration, tunnelAllowed: connected))
                record.expectedRules = try ownRules()
                guard record.expectedRules.contains("mamori-default-deny") else { throw GuardFailure.message("The updated block policy could not be verified.") }
                try JournalStore.save(record)
                journal = record
                lastTunnelAllowed = connected
            }
            status = GuardStatus(phase: connected ? .protected : .blocked,
                message: connected ? "GlobalProtect verified. Direct network traffic is blocked." : "VPN unavailable. Network traffic remains blocked except approved VPN transport and DHCP.",
                configuration: record.configuration, helperAvailable: true)
        } catch { fault(error.localizedDescription) }
    }

    private func restore() {
        if journal == nil {
            do {
                journal = try JournalStore.load()
                if journal == nil {
                    guard try ownRules().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw GuardFailure.message("Owned firewall rules exist without a readable recovery journal. Restoration cannot be confirmed.")
                    }
                    status = GuardStatus(phase: .inactive, message: "Network protection is inactive.", helperAvailable: true)
                    return
                }
            } catch { fault(error.localizedDescription); return }
        }
        guard var record = journal else { return }
        do {
            record.desiredArmed = false
            try JournalStore.save(record)
            journal = record
            _ = try Commands.pf(["-a", GuardIdentity.anchor, "-F", "rules"])
            guard try ownRules().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GuardFailure.message("Mamori's firewall rules are still present. Restore was not completed.") }
            if record.enableRequested && record.token == nil {
                throw GuardFailure.message("The PF enable reference is uncertain after an interrupted activation. Owned rules are removed, but automatic reference cleanup cannot be confirmed.")
            }
            if let token = record.token {
                guard token.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else { throw GuardFailure.message("The saved enable reference is invalid.") }
                _ = try Commands.pf(["-X", token])
                record.token = nil
                record.enableRequested = false
                journal = record
                try JournalStore.save(record)
            }
            try JournalStore.remove()
            journal = nil
            lastTunnelAllowed = nil
            status = GuardStatus(phase: .inactive, message: "Mamori's network settings have been restored.", helperAvailable: true)
        } catch { fault(error.localizedDescription + " Mamori will keep the recovery journal for retry.") }
    }
}

final class GuardPeer: NSObject, GuardXPCProtocol, @unchecked Sendable {
    private let engine: GuardEngine
    private let uid: uid_t
    init(engine: GuardEngine, uid: uid_t) { self.engine = engine; self.uid = uid }
    func getStatus(reply: @escaping @Sendable (Data) -> Void) { engine.perform("status", uid: uid, reply: reply) }
    func start(configuration: Data, reply: @escaping @Sendable (Data) -> Void) { engine.perform("start", configuration: configuration, uid: uid, reply: reply) }
    func stop(reply: @escaping @Sendable (Data) -> Void) { engine.perform("stop", uid: uid, reply: reply) }
    func prepareUninstall(reply: @escaping @Sendable (Data) -> Void) { engine.perform("uninstall", uid: uid, reply: reply) }
}

final class GuardListener: NSObject, NSXPCListenerDelegate {
    private let engine = GuardEngine()
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier >= 501 else { return false }
        connection.exportedInterface = NSXPCInterface(with: GuardXPCProtocol.self)
        connection.exportedObject = GuardPeer(engine: engine, uid: connection.effectiveUserIdentifier)
        connection.resume()
        return true
    }
}
