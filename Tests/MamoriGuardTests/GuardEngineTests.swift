import XCTest
import MamoriCore
@testable import MamoriGuardSupport

private final class MemoryJournal: GuardJournalStoring, @unchecked Sendable {
    var value: GuardJournal?
    var removed = false
    var failSave = false
    var failRemove = false
    func load() throws -> GuardJournal? { value }
    func save(_ journal: GuardJournal) throws {
        if failSave { throw GuardFailure.message("Injected journal write failure") }
        value = journal
    }
    func remove() throws {
        if failRemove { throw GuardFailure.message("Injected directory removal failure") }
        value = nil; removed = true
    }
}

private final class FakeVPN: GuardVPNVerifying, @unchecked Sendable {
    var connection: GuardVPNState = .connected
    func discover() -> GuardDiscovery { GuardDiscovery(message: "Fixture only") }
    func state(for configuration: GuardConfiguration, requireEndpoints: Bool) -> GuardVPNState { connection }
}

private final class FakePF: GuardCommandRunning, @unchecked Sendable {
    var enabled = false
    var root = "anchor \"com.apple/*\" all\n"
    var rules = ""
    var states = ""
    var mutations: [[String]] = []
    var loadedPolicies: [String] = []
    var corruptLoad = false
    var failFlush = false
    var failRelease = false
    var references = Set<String>()
    var referencesOutput: String?
    var failReferenceReadAfterRelease = false
    var retainReleasedReference = false
    func run(_ executable: String, _ arguments: [String], input: String?) throws -> CommandResult {
        guard executable == "/sbin/pfctl" else { throw GuardFailure.message("Unexpected executable in inert test") }
        var output = ""
        if arguments == ["-s", "info"] { output = "Status: \(enabled ? "Enabled" : "Disabled")\n" }
        else if arguments == ["-s", "References"] {
            if failReferenceReadAfterRelease && mutations.contains(["-X", "123"]) { throw GuardFailure.message("Injected reference read failure") }
            output = referencesOutput ?? (references.isEmpty ? "No pf starter references held\n" :
                "TOKENS:\nPID      Process Name                 TOKEN                    TIMESTAMP\n" +
                references.sorted().map { "42       MamoriGuard                  \($0)                      0 days 00:00:01\n" }.joined())
        }
        else if arguments == ["-s", "states"] { output = states }
        else if arguments == ["-v", "-s", "Interfaces"] { output = "lo0\nutun9\nen0\n" }
        else if arguments == ["-s", "rules"] { output = root }
        else if arguments == ["-a", "*", "-s", "rules"] { output = root.trimmingCharacters(in: .whitespacesAndNewlines) + " {\n" + rules + "}\n" }
        else if arguments == ["-a", GuardIdentity.anchor, "-s", "rules"] { output = rules }
        else if arguments.contains("-n") { output = input ?? "" }
        else if arguments.contains("-f") {
            mutations.append(arguments)
            rules = (input ?? "") + (corruptLoad ? "pass quick all\n" : "")
            loadedPolicies.append(rules)
        } else if arguments == ["-E"] {
            mutations.append(arguments); enabled = true; references.insert("123"); output = "Token : 123\n"
        } else if arguments == ["-a", GuardIdentity.anchor, "-F", "rules"] {
            if failFlush { throw GuardFailure.message("Injected flush failure") }
            mutations.append(arguments); rules = ""
        } else if arguments == ["-X", "123"] {
            if failRelease { throw GuardFailure.message("Injected reference release failure") }
            guard references.contains("123") else { throw GuardFailure.message("PF token invalid: already consumed") }
            mutations.append(arguments)
            if !retainReleasedReference { references.remove("123") }
            enabled = !references.isEmpty
        } else { throw GuardFailure.message("Unexpected PF arguments in inert test: \(arguments)") }
        return CommandResult(code: 0, output: output, error: "")
    }
}

final class GuardEngineTests: XCTestCase, @unchecked Sendable {
    private let configuration = GuardConfiguration(tunnelInterface: "utun9", gatewayAddresses: ["203.0.113.4"])
    private func engine(_ pf: FakePF, _ store: MemoryJournal, _ vpn: FakeVPN = FakeVPN()) -> GuardEngine {
        GuardEngine(commands: pf, store: store, vpn: vpn, bootIdentifier: { "boot-A" }, startTimer: false, onIdle: {})
    }
    private func request(_ engine: GuardEngine, _ action: String, uid: UInt32 = 501) async throws -> GuardStatus {
        let data = action == "start" ? try JSONEncoder().encode(configuration) : nil
        return try await withCheckedThrowingContinuation { continuation in
            engine.perform(action, configuration: data, uid: uid) { data in
                do { continuation.resume(returning: try JSONDecoder().decode(GuardStatus.self, from: data)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    func testManualDisconnectRetainsPhysicalDefaultDenyAndNarrowsTunnel() async throws {
        let pf = FakePF(), store = MemoryJournal(), vpn = FakeVPN(), guardEngine = engine(pf, store, vpn)
        let active = try await request(guardEngine, "start")
        XCTAssertEqual(active.phase, .protected, active.message)
        XCTAssertEqual(pf.mutations.last, ["-E"])
        XCTAssertTrue(pf.loadedPolicies.first?.contains("block drop quick all") == true)
        vpn.connection = .disconnected
        let blocked = try await request(guardEngine, "status")
        XCTAssertEqual(blocked.phase, .blocked)
        XCTAssertEqual(blocked.vpnState, .disconnected)
        XCTAssertTrue(pf.enabled)
        XCTAssertTrue(pf.rules.contains("mamori-default-deny"))
        XCTAssertFalse(pf.rules.contains("mamori-tunnel"))
        XCTAssertFalse(pf.rules.contains("on en0"))
        XCTAssertTrue(pf.loadedPolicies.allSatisfy { $0.contains("block drop quick all") })
        XCTAssertFalse(pf.mutations.contains { $0.contains("-F") || $0.contains("-X") })
    }
    func testUnreadableVPNEvidenceBlocksWithoutConfirmingLoss() async throws {
        let pf = FakePF(), store = MemoryJournal(), vpn = FakeVPN(), guardEngine = engine(pf, store, vpn)
        _ = try await request(guardEngine, "start")
        vpn.connection = .unconfirmed
        let blocked = try await request(guardEngine, "status")
        XCTAssertEqual(blocked.phase, .blocked)
        XCTAssertEqual(blocked.vpnState, .unconfirmed)
    }
    func testUnexpectedLoadedRuleNeverEnablesPF() async throws {
        let pf = FakePF(), store = MemoryJournal()
        pf.corruptLoad = true
        let result = try await request(engine(pf, store), "start")
        XCTAssertEqual(result.phase, .fault)
        XCTAssertFalse(pf.enabled)
        XCTAssertFalse(pf.mutations.contains(["-E"]))
        XCTAssertNotNil(store.value)
    }
    func testJournalFailureOccursBeforeAnyKernelMutation() async throws {
        let pf = FakePF(), store = MemoryJournal()
        store.failSave = true
        let result = try await request(engine(pf, store), "start")
        XCTAssertEqual(result.phase, .fault)
        XCTAssertTrue(pf.mutations.isEmpty)
    }
    func testFailedFlushNeverReleasesReferenceOrAcknowledgesRestore() async throws {
        let pf = FakePF(), store = MemoryJournal(), guardEngine = engine(pf, store)
        _ = try await request(guardEngine, "start")
        pf.failFlush = true
        let result = try await request(guardEngine, "stop")
        XCTAssertEqual(result.phase, .fault)
        XCTAssertEqual(store.value?.desiredArmed, false)
        XCTAssertTrue(pf.enabled)
        XCTAssertFalse(pf.mutations.contains(["-X", "123"]))
    }
    func testSuccessfulRestoreOnlyRemovesOwnedRulesAndReference() async throws {
        let pf = FakePF(), store = MemoryJournal(), guardEngine = engine(pf, store)
        _ = try await request(guardEngine, "start")
        let restored = try await request(guardEngine, "stop")
        XCTAssertEqual(restored.phase, .inactive)
        XCTAssertTrue(store.removed)
        XCTAssertTrue(pf.rules.isEmpty)
        XCTAssertEqual(pf.mutations.suffix(2), [["-a", GuardIdentity.anchor, "-F", "rules"], ["-X", "123"]])
        XCTAssertFalse(pf.mutations.contains(["-d"]))
    }
    func testUninstallWithoutJournalStillVerifiesPrivateDirectoryRemoval() async throws {
        let pf = FakePF(), store = MemoryJournal()
        store.failRemove = true
        let result = try await request(engine(pf, store), "uninstall")
        XCTAssertEqual(result.phase, .fault)
        XCTAssertTrue(pf.mutations.isEmpty)
    }
    func testUnknownAnchorChangesAreNotFlushedOnStop() async throws {
        let pf = FakePF(), store = MemoryJournal(), guardEngine = engine(pf, store)
        _ = try await request(guardEngine, "start")
        pf.rules += "pass quick all\n"
        let result = try await request(guardEngine, "stop")
        XCTAssertEqual(result.phase, .fault)
        XCTAssertFalse(pf.mutations.contains { $0.contains("-F") || $0.contains("-X") })
    }
    func testDifferentUserCannotStopTheSession() async throws {
        let pf = FakePF(), store = MemoryJournal(), guardEngine = engine(pf, store)
        _ = try await request(guardEngine, "start")
        let result = try await request(guardEngine, "stop", uid: 502)
        XCTAssertEqual(result.phase, .fault)
        XCTAssertEqual(store.value?.desiredArmed, true)
        XCTAssertTrue(pf.enabled)
    }
    func testReleaseFailureRetainsJournalUntilRetryAcknowledgesCleanup() async throws {
        let pf = FakePF(), store = MemoryJournal(), guardEngine = engine(pf, store)
        _ = try await request(guardEngine, "start")
        pf.failRelease = true
        let failed = try await request(guardEngine, "stop")
        XCTAssertEqual(failed.phase, .fault)
        XCTAssertEqual(store.value?.token, "123")
        XCTAssertTrue(pf.rules.isEmpty)
        XCTAssertFalse(store.removed)
        pf.failRelease = false
        let restored = try await request(guardEngine, "stop")
        XCTAssertEqual(restored.phase, .inactive)
        XCTAssertTrue(store.removed)
    }
    func testCrashAfterReferenceReleaseRecoversFromExactAbsence() async throws {
        let pf = FakePF(), store = MemoryJournal()
        store.value = GuardJournal(configuration: configuration, ownerUID: 501, desiredArmed: false,
            token: "123", enableRequested: true, expectedRules: try GuardPolicy.render(configuration, tunnelAllowed: true),
            rootRules: pf.root, bootIdentifier: "boot-A")
        // Same boot, rules already removed, -X already consumed. A different token
        // whose digits include the saved token must not be mistaken for our reference.
        pf.references = ["1234"]; pf.enabled = true
        let restored = try await request(engine(pf, store), "stop")
        XCTAssertEqual(restored.phase, .inactive, restored.message)
        XCTAssertTrue(store.removed)
        XCTAssertTrue(pf.enabled)
        XCTAssertEqual(pf.references, ["1234"])
        XCTAssertTrue(pf.mutations.isEmpty)
    }
    func testUnreadableReferenceListNeverGuessesReleaseOrCleanup() async throws {
        let pf = FakePF(), store = MemoryJournal(), guardEngine = engine(pf, store)
        _ = try await request(guardEngine, "start")
        pf.referencesOutput = ""
        let failed = try await request(guardEngine, "stop")
        XCTAssertEqual(failed.phase, .fault)
        XCTAssertEqual(store.value?.token, "123")
        XCTAssertFalse(store.removed)
        XCTAssertFalse(pf.mutations.contains(["-X", "123"]))
    }
    func testPostReleaseReadFailureRetainsJournalAndRetrySkipsConsumedToken() async throws {
        let pf = FakePF(), store = MemoryJournal(), guardEngine = engine(pf, store)
        _ = try await request(guardEngine, "start")
        pf.failReferenceReadAfterRelease = true
        let failed = try await request(guardEngine, "stop")
        XCTAssertEqual(failed.phase, .fault)
        XCTAssertEqual(store.value?.token, "123")
        XCTAssertTrue(pf.references.isEmpty)
        pf.failReferenceReadAfterRelease = false
        let restored = try await request(guardEngine, "stop")
        XCTAssertEqual(restored.phase, .inactive, restored.message)
        XCTAssertEqual(pf.mutations.filter { $0 == ["-X", "123"] }.count, 1)
        XCTAssertTrue(store.removed)
    }
    func testReferenceStillPresentAfterSuccessfulReleaseIsNotAcknowledged() async throws {
        let pf = FakePF(), store = MemoryJournal(), guardEngine = engine(pf, store)
        _ = try await request(guardEngine, "start")
        pf.retainReleasedReference = true
        let failed = try await request(guardEngine, "stop")
        XCTAssertEqual(failed.phase, .fault)
        XCTAssertEqual(store.value?.token, "123")
        XCTAssertFalse(store.removed)
    }
    func testOtherRootPolicyPreventsDestructiveRestoration() async throws {
        let pf = FakePF(), store = MemoryJournal(), guardEngine = engine(pf, store)
        _ = try await request(guardEngine, "start")
        pf.root += "pass quick all\n"
        let failed = try await request(guardEngine, "stop")
        XCTAssertEqual(failed.phase, .fault)
        XCTAssertFalse(pf.mutations.contains { $0.contains("-F") || $0.contains("-X") })
        XCTAssertTrue(pf.rules.contains("mamori-default-deny"))
    }
    func testOldBootReferenceIsNeverReleasedAgainstCurrentKernel() async throws {
        let pf = FakePF(), store = MemoryJournal()
        store.value = GuardJournal(configuration: configuration, ownerUID: 501, token: "123", enableRequested: true,
            expectedRules: try GuardPolicy.render(configuration, tunnelAllowed: true), rootRules: pf.root, bootIdentifier: "boot-previous")
        let guardEngine = engine(pf, store)
        let status = try await request(guardEngine, "status")
        XCTAssertEqual(status.phase, .fault)
        let restored = try await request(guardEngine, "stop")
        XCTAssertEqual(restored.phase, .inactive)
        XCTAssertTrue(pf.mutations.isEmpty)
        XCTAssertTrue(store.removed)
    }
    func testInterruptedEnableWithoutTokenNeverGuessesGlobalDisable() async throws {
        let pf = FakePF(), store = MemoryJournal()
        pf.rules = try GuardPolicy.render(configuration, tunnelAllowed: true)
        pf.enabled = true
        store.value = GuardJournal(configuration: configuration, ownerUID: 501, enableRequested: true,
            expectedRules: pf.rules, rootRules: pf.root, bootIdentifier: "boot-A")
        let result = try await request(engine(pf, store), "stop")
        XCTAssertEqual(result.phase, .fault)
        XCTAssertTrue(pf.enabled)
        XCTAssertTrue(pf.rules.isEmpty)
        XCTAssertNotNil(store.value)
        XCTAssertFalse(pf.mutations.contains { $0.contains("-X") || $0.contains("-d") })
    }
    func testInterruptedPolicyCommitRecoversOnlyRecordedNewPolicy() async throws {
        let pf = FakePF(), store = MemoryJournal(), vpn = FakeVPN()
        vpn.connection = .disconnected
        let old = try GuardPolicy.render(configuration, tunnelAllowed: true)
        let narrowed = try GuardPolicy.render(configuration, tunnelAllowed: false)
        pf.rules = narrowed; pf.enabled = true
        store.value = GuardJournal(configuration: configuration, ownerUID: 501, token: "123", enableRequested: true,
            expectedRules: old, rootRules: pf.root, pendingRules: narrowed, bootIdentifier: "boot-A")
        let result = try await request(engine(pf, store, vpn), "status")
        XCTAssertEqual(result.phase, .blocked)
        XCTAssertEqual(store.value?.expectedRules, narrowed)
        XCTAssertNil(store.value?.pendingRules)
        XCTAssertTrue(pf.mutations.isEmpty)
    }
}

final class GuardEvidenceTests: XCTestCase {
    func testReferencesAcceptOnlyCompleteRecognizedRepresentations() throws {
        XCTAssertEqual(try PFReferences.tokens(in: "No pf_enabled references\n"), [])
        XCTAssertEqual(try PFReferences.tokens(in: "No pf starter references held\n"), [])
        let table = "TOKENS:\nPID      Process Name                 TOKEN                    TIMESTAMP\n" +
            "501      Name with spaces             18446744073709551615     12 days 01:02:03\n" +
            "502      Another                      123                      0 days 00:00:01\n"
        XCTAssertEqual(try PFReferences.tokens(in: table), ["18446744073709551615", "123"])
        for unreadable in ["", "permission denied", "TOKENS:\nPID Process Name TOKEN TIMESTAMP\n",
                           table + "truncated row\n", table + "503 Other 123 0 days 00:00:01\n"] {
            XCTAssertThrowsError(try PFReferences.tokens(in: unreadable))
        }
    }
    func testMultipleGlobalProtectInterfacesAreAmbiguousRatherThanDisconnected() {
        XCTAssertEqual(GlobalProtectVerifier.classify(interfaces: ["utun9", "utun10"], selected: "utun9"), .unconfirmed)
        XCTAssertEqual(GlobalProtectVerifier.classify(interfaces: ["utun10", "utun11"], selected: "utun9"), .unconfirmed)
        XCTAssertEqual(GlobalProtectVerifier.classify(interfaces: ["utun9"], selected: "utun9"), .connected)
        XCTAssertEqual(GlobalProtectVerifier.classify(interfaces: ["utun10"], selected: "utun9"), .disconnected)
        XCTAssertEqual(GlobalProtectVerifier.classify(interfaces: [], selected: "utun9"), .disconnected)
    }
}
