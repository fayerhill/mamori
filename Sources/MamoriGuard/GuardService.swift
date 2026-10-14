import Foundation
import MamoriCore
import Darwin

/// macOS pfctl's C-locale `-s References` output, checked against the shipped tool.
/// Unknown or incomplete output must never be interpreted as an absent reference.
enum PFReferences {
    static func tokens(in output: String) throws -> Set<String> {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if lines == ["No pf_enabled references"] || lines == ["No pf starter references held"] { return [] }
        guard lines.count >= 3, lines[0] == "TOKENS:",
              lines[1].split(whereSeparator: \.isWhitespace).joined(separator: " ") == "PID Process Name TOKEN TIMESTAMP" else {
            throw GuardFailure.message("PF enable references could not be verified. The saved reference is retained for retry.")
        }
        let row = try NSRegularExpression(pattern: #"\A[0-9]+\s+\S(?:.*\S)?\s+([0-9]+)\s+[0-9]+ days [0-9]{2}:[0-9]{2}:[0-9]{2}\z"#)
        var tokens = Set<String>()
        for line in lines.dropFirst(2) {
            guard let match = row.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let range = Range(match.range(at: 1), in: line), let token = UInt64(line[range]),
                  tokens.insert(String(token)).inserted else {
                throw GuardFailure.message("PF enable references have an unsupported representation. The saved reference is retained for retry.")
            }
        }
        return tokens
    }
}

final class GuardEngine: @unchecked Sendable {
    let queue = DispatchQueue(label: "com.mamori.guard.state")
    private let commands: any GuardCommandRunning
    private let store: any GuardJournalStoring
    private let vpn: any GuardVPNVerifying
    private let bootIdentifier: @Sendable () throws -> String
    private let onIdle: @Sendable () -> Void
    private var journal: GuardJournal?
    private var status = GuardStatus(phase: .inactive, message: "Network protection is inactive.", helperAvailable: true)
    private var timer: DispatchSourceTimer?
    private var lastTunnelAllowed: Bool?

    init(commands: any GuardCommandRunning = ProcessCommandRunner(), store: any GuardJournalStoring = FileJournalStore(),
         vpn: any GuardVPNVerifying = GlobalProtectVerifier(), bootIdentifier: @escaping @Sendable () throws -> String = currentBootIdentifier,
         startTimer: Bool = true, onIdle: @escaping @Sendable () -> Void = { exit(0) }) {
        self.commands = commands; self.store = store; self.vpn = vpn
        self.bootIdentifier = bootIdentifier; self.onIdle = onIdle
        queue.async { [self] in
            do {
                journal = try store.load()
                if let journal {
                    fault("A previous guard session needs verification.")
                    if journal.desiredArmed { refresh() } else { restore() }
                }
            } catch { fault(error.localizedDescription) }
            if startTimer {
                let timer = DispatchSource.makeTimerSource(queue: queue)
                timer.schedule(deadline: .now() + 3, repeating: 3, leeway: .milliseconds(300))
                timer.setEventHandler { [weak self] in if self?.journal?.desiredArmed == true { self?.refresh() } }
                timer.resume()
                self.timer = timer
            }
        }
    }

    func discover(uid: uid_t, reply: @escaping @Sendable (Data) -> Void) {
        queue.async { [self] in
            if let owner = journal?.ownerUID, owner != uid {
                reply(encode(GuardDiscovery(message: "This guard session belongs to another signed-in user.")))
            } else { reply(encode(vpn.discover())) }
        }
    }

    func perform(_ action: String, configuration: Data? = nil, uid: uid_t, reply: @escaping @Sendable (Data) -> Void) {
        queue.async { [self] in
            if let owner = journal?.ownerUID, owner != uid {
                reply(encode(GuardStatus(phase: .fault, message: "This guard session belongs to another signed-in user.", helperAvailable: true)))
                return
            }
            switch action {
            case "start":
                if let configuration { arm(configuration, uid: uid) } else { fault("A guard configuration is required.") }
            case "stop", "uninstall": restore(requestingUID: uid)
            default: if journal?.desiredArmed == true { refresh() }
            }
            reply(encode(status))
            if (action == "stop" || action == "uninstall") && status.phase == .inactive {
                queue.asyncAfter(deadline: .now() + 2) { [weak self] in
                    guard let self, self.journal == nil else { return }
                    self.onIdle()
                }
            }
        }
    }

    private func encode<T: Encodable>(_ value: T) -> Data { (try? JSONEncoder().encode(value)) ?? Data() }
    private func fault(_ message: String) {
        status = GuardStatus(phase: .fault, message: message, configuration: journal?.configuration, helperAvailable: true)
    }
    private func persist(_ value: GuardJournal) throws {
        journal = value
        try store.save(value)
    }
    private func pfState() throws -> (enabled: Bool, count: Int) {
        let info = try commands.pfRead(["-s", "info"])
        guard let enabled = info.range(of: #"Status:\s+(Enabled|Disabled)"#, options: .regularExpression) else { throw GuardFailure.message("PF status could not be read.") }
        let states = try commands.pfRead(["-s", "states"])
        return (info[enabled].contains("Enabled"), states.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
    }
    private func verifyNoSkipInterfaces() throws {
        let interfaces = try commands.pfRead(["-v", "-s", "Interfaces"])
        guard !interfaces.lowercased().contains("skip") else { throw GuardFailure.message("PF has interface skip settings. Mamori cannot establish complete packet filtering.") }
    }
    private func ownRules() throws -> String { try PFRuleInspector(commands: commands).readOwnedRules() }
    private func enableReferences() throws -> Set<String> {
        let result = try commands.run("/sbin/pfctl", ["-s", "References"])
        guard result.code == 0 else { throw GuardFailure.message("PF enable references could not be read. The saved reference is retained for retry.") }
        // Some system versions print the recognized empty-list notice to stderr.
        return try PFReferences.tokens(in: result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? result.error : result.output)
    }
    private func compiledPolicy(_ configuration: GuardConfiguration, tunnelAllowed: Bool) throws -> (source: String, compiled: String) {
        let source = try GuardPolicy.render(configuration, tunnelAllowed: tunnelAllowed)
        let compiled = try commands.pfCompilePolicy(source)
        guard GuardPolicy.validCompiledPolicy(compiled, tunnelAllowed: tunnelAllowed) else { throw GuardFailure.message("The PF parser returned an unsupported policy representation. No protection was activated.") }
        return (source, compiled)
    }
    private func verifyGlobalRules(root: String, owned: String) throws {
        let snapshot = try PFRuleInspector(commands: commands).read()
        guard GuardPolicy.meaningfulLines(snapshot.rootRules) == GuardPolicy.meaningfulLines(root),
              GuardPolicy.containsOnlyOwnedFilterRules(snapshot.anchorRules, expectedOwnRules: owned) else {
            throw GuardFailure.message("Another firewall policy changed. Mamori will not overwrite or disable it.")
        }
    }

    private func arm(_ data: Data, uid: uid_t) {
        guard journal == nil else { fault("A guard session already exists. Restore it before starting another."); return }
        do {
            guard try store.load() == nil else { throw GuardFailure.message("A persisted guard session needs restoration before starting.") }
            guard data.count <= 8192 else { throw GuardFailure.message("The guard configuration is too large.") }
            let config = try JSONDecoder().decode(GuardConfiguration.self, from: data)
            try GuardPolicy.validate(config)
            guard vpn.state(for: config, requireEndpoints: true) == .connected else { throw GuardFailure.message("The selected tunnel and gateway could not be verified as the active GlobalProtect connection. Connect GlobalProtect first and detect its configuration.") }
            let pf = try pfState()
            try verifyNoSkipInterfaces()
            let snapshot = try PFRuleInspector(commands: commands).read()
            let root = snapshot.rootRules
            try GuardPolicy.preflight(rootRules: root, anchorRules: snapshot.anchorRules, pfEnabled: pf.enabled, stateCount: pf.count)
            guard try ownRules().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GuardFailure.message("Mamori's anchor is already occupied. Restore the previous session first.") }
            let policy = try compiledPolicy(config, tunnelAllowed: true)
            var record = GuardJournal(configuration: config, ownerUID: uid, expectedRules: policy.compiled, rootRules: root, bootIdentifier: try bootIdentifier())
            try persist(record)
            status = GuardStatus(phase: .arming, message: "Preparing the network guard.", configuration: config, helperAvailable: true)
            _ = try commands.pf(["-a", GuardIdentity.anchor, "-o", "none", "-f", "-"], input: policy.source)
            guard try GuardPolicy.rulesMatch(ownRules(), policy.compiled) else { throw GuardFailure.message("The loaded policy differs from the intended policy. Protection was not activated.") }
            let beforeEnable = try pfState()
            guard !beforeEnable.enabled, beforeEnable.count == 0 else { throw GuardFailure.message("PF changed during setup. Protection was not activated.") }
            try verifyNoSkipInterfaces()
            try verifyGlobalRules(root: root, owned: policy.compiled)
            record.enableRequested = true
            try persist(record)
            let result = try commands.run("/sbin/pfctl", ["-E"])
            let combined = result.output + "\n" + result.error
            let expression = try NSRegularExpression(pattern: #"Token\s*:\s*([0-9]+)"#)
            guard result.code == 0, let match = expression.firstMatch(in: combined, range: NSRange(combined.startIndex..., in: combined)), let range = Range(match.range(at: 1), in: combined) else {
                throw GuardFailure.message("PF did not return a usable enable reference. Keep Mamori installed and retry restoration; its global enable state cannot be safely guessed.")
            }
            record.token = String(combined[range])
            try persist(record)
            lastTunnelAllowed = true
            refresh()
        } catch { fault(error.localizedDescription) }
    }

    private func refresh() {
        guard var record = journal, record.desiredArmed else { return }
        do {
            guard record.bootIdentifier == (try bootIdentifier()) else { throw GuardFailure.message("This session belongs to a previous or unknown boot. Protection is not active for this boot. Restore the previous session before starting again.") }
            let pf = try pfState()
            try verifyNoSkipInterfaces()
            guard pf.enabled, pf.count == 0, GuardPolicy.mayResumeProtection(desiredArmed: record.desiredArmed, token: record.token, rulesMatch: true) else {
                throw GuardFailure.message("The firewall changed or could not be verified. Existing Mamori rules are retained; protection is not confirmed.")
            }
            let current = try ownRules()
            if let pending = record.pendingRules {
                if GuardPolicy.rulesMatch(current, pending) { record.expectedRules = pending }
                else if !GuardPolicy.rulesMatch(current, record.expectedRules) { throw GuardFailure.message("An interrupted policy update cannot be reconciled. Restore the session before continuing.") }
                record.pendingRules = nil
                try persist(record)
            }
            guard GuardPolicy.rulesMatch(current, record.expectedRules) else { throw GuardFailure.message("Mamori's policy was changed. Protection is not confirmed.") }
            try verifyGlobalRules(root: record.rootRules, owned: record.expectedRules)
            let vpnState = vpn.state(for: record.configuration, requireEndpoints: false)
            let connected = vpnState == .connected
            if lastTunnelAllowed != connected {
                let policy = try compiledPolicy(record.configuration, tunnelAllowed: connected)
                if !GuardPolicy.rulesMatch(record.expectedRules, policy.compiled) {
                    record.pendingRules = policy.compiled
                    try persist(record)
                    _ = try commands.pf(["-a", GuardIdentity.anchor, "-o", "none", "-f", "-"], input: policy.source)
                    guard try GuardPolicy.rulesMatch(ownRules(), policy.compiled) else { throw GuardFailure.message("The updated block policy could not be verified.") }
                    try verifyGlobalRules(root: record.rootRules, owned: policy.compiled)
                    record.expectedRules = policy.compiled
                    record.pendingRules = nil
                    try persist(record)
                }
                lastTunnelAllowed = connected
            }
            status = GuardStatus(phase: connected ? .protected : .blocked,
                message: connected ? "GlobalProtect verified. Direct network traffic is blocked." : "The selected VPN is unavailable or unconfirmed. Direct network traffic remains blocked except approved VPN transport and DHCP.",
                configuration: record.configuration, helperAvailable: true, vpnState: vpnState)
        } catch { fault(error.localizedDescription) }
    }

    private func restore(requestingUID: uid_t? = nil) {
        do {
            if journal == nil { journal = try store.load() }
            guard var record = journal else {
                guard try ownRules().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GuardFailure.message("Owned rules exist without a readable journal. Keep Mamori installed; restoration requires recovery.") }
                try store.remove()
                status = GuardStatus(phase: .inactive, message: "Network protection is inactive and Mamori's recovery data is removed.", helperAvailable: true)
                return
            }
            if let requestingUID, requestingUID != record.ownerUID { throw GuardFailure.message("This guard session belongs to another signed-in user.") }
            record.desiredArmed = false
            try persist(record)
            let current = try ownRules()
            let empty = current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let boot = try bootIdentifier()
            if let previousBoot = record.bootIdentifier, previousBoot != boot {
                guard empty else { throw GuardFailure.message("A previous-boot journal cannot authorize removal of current firewall rules. Keep the journal for recovery.") }
                record.token = nil
                record.enableRequested = false
                try persist(record)
            } else {
                guard empty || GuardPolicy.rulesMatch(current, record.expectedRules) || record.pendingRules.map({ GuardPolicy.rulesMatch(current, $0) }) == true else {
                    throw GuardFailure.message("The owned anchor no longer matches either recorded policy. Mamori will not flush unknown rules.")
                }
                if record.token != nil {
                    guard record.bootIdentifier == boot else { throw GuardFailure.message("The saved PF reference has no verified boot identity. Keep Mamori installed; automatic reference cleanup is unavailable.") }
                    try verifyGlobalRules(root: record.rootRules, owned: current)
                }
                if !empty { _ = try commands.pf(["-a", GuardIdentity.anchor, "-F", "rules"]) }
                guard try ownRules().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw GuardFailure.message("Mamori's firewall rules are still present. Restore was not completed.") }
                if record.enableRequested && record.token == nil {
                    throw GuardFailure.message("Mamori's blocking rules are removed, but an interrupted activation left its PF enable reference unknown. Keep the app and recovery journal; do not disable the entire firewall. Automatic cleanup can resume after a normal reboot.")
                }
                if let token = record.token {
                    guard let numericToken = UInt64(token), String(numericToken) == token else { throw GuardFailure.message("The saved enable reference is invalid.") }
                    // A previous -X may have succeeded immediately before the helper crashed.
                    // Exact absence in the same boot is idempotent success, not a reason to
                    // guess or disable PF globally. A failed release stays retryable.
                    if try enableReferences().contains(token) {
                        _ = try commands.pf(["-X", token])
                        guard try !enableReferences().contains(token) else {
                            throw GuardFailure.message("Mamori's PF enable reference is still present. Restoration is not confirmed.")
                        }
                    }
                    record.token = nil
                    record.enableRequested = false
                    try persist(record)
                }
            }
            try store.remove()
            journal = nil
            lastTunnelAllowed = nil
            status = GuardStatus(phase: .inactive, message: "Mamori's network settings and recovery data have been restored.", helperAvailable: true)
        } catch { fault(error.localizedDescription + " Recovery information is retained for retry.") }
    }
}

private final class GuardPeer: NSObject, GuardXPCProtocol, @unchecked Sendable {
    private let engine: GuardEngine
    private let uid: uid_t
    init(engine: GuardEngine, uid: uid_t) { self.engine = engine; self.uid = uid }
    func discoverConfiguration(reply: @escaping @Sendable (Data) -> Void) { engine.discover(uid: uid, reply: reply) }
    func getStatus(reply: @escaping @Sendable (Data) -> Void) { engine.perform("status", uid: uid, reply: reply) }
    func start(configuration: Data, reply: @escaping @Sendable (Data) -> Void) { engine.perform("start", configuration: configuration, uid: uid, reply: reply) }
    func stop(reply: @escaping @Sendable (Data) -> Void) { engine.perform("stop", uid: uid, reply: reply) }
    func prepareUninstall(reply: @escaping @Sendable (Data) -> Void) { engine.perform("uninstall", uid: uid, reply: reply) }
}

public final class GuardListener: NSObject, NSXPCListenerDelegate {
    private let engine = GuardEngine()
    public override init() { super.init() }
    public func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier >= 501 else { return false }
        connection.exportedInterface = NSXPCInterface(with: GuardXPCProtocol.self)
        connection.exportedObject = GuardPeer(engine: engine, uid: connection.effectiveUserIdentifier)
        connection.resume()
        return true
    }
}
