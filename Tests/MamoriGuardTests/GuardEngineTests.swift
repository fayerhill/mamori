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
    var requests: [[String]] = []
    var loadedPolicies: [String] = []
    var corruptLoad = false
    var failFlush = false
    var failRelease = false
    var references = Set<String>()
    var referencesOutput: String?
    var failReferenceReadAfterRelease = false
    var retainReleasedReference = false
    var anchorListings = ["": ["com.apple"], "com.apple": ["com.apple/200.AirDrop", "com.apple/250.ApplicationFirewall"]]
    var anchorContents = ["com.apple": "anchor \"200.AirDrop/*\" all\nanchor \"250.ApplicationFirewall/*\" all\n"]
    var readDiagnosticArguments: [String]?
    var readDiagnostic = "pfctl: DIOCGETRULES: Invalid argument\n"
    var changeTopologyAfterFirstRead = false
    var compileExitCode: Int32 = 0
    var compileDiagnostics = "pfctl: Use of -f option, could result in flushing of rules\npresent in the main ruleset added by the system at startup.\nSee /etc/pf.conf for further details.\n\n"
    private var rootListReads = 0
    func run(_ executable: String, _ arguments: [String], input: String?) throws -> CommandResult {
        guard executable == "/sbin/pfctl" else { throw GuardFailure.message("Unexpected executable in inert test") }
        requests.append(arguments)
        if arguments == readDiagnosticArguments {
            return CommandResult(code: 0, output: "anchor \"*\" all {\n}\n", error: readDiagnostic)
        }
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
        else if arguments == ["-a", "*", "-s", "rules"] {
            // Actual host failure: partial recursive output despite a zero exit code.
            return CommandResult(code: 0, output: "scrub-anchor \"com.apple/*\" all fragment reassemble\nanchor \"*\" all {\n}\n", error: "No ALTQ support in kernel\nALTQ related functions disabled\npfctl: DIOCGETRULES: Invalid argument\n")
        }
        else if arguments == ["-a", GuardIdentity.anchor, "-s", "rules"] {
            // macOS does not represent a nonexistent anchor as a successful empty read.
            if rules.isEmpty && !(anchorListings["com.apple"] ?? []).contains(GuardIdentity.anchor) {
                return CommandResult(code: 0, output: "", error: "No ALTQ support in kernel\nALTQ related functions disabled\npfctl: DIOCGETRULES: Invalid argument\n")
            }
            output = rules
        }
        else if arguments.last == "Anchors" {
            let path = arguments.first == "-a" ? arguments[1] : ""
            var children = anchorListings[path] ?? []
            if path == "com.apple", !rules.isEmpty, !children.contains(GuardIdentity.anchor) { children.insert(GuardIdentity.anchor, at: 0) }
            if path.isEmpty {
                rootListReads += 1
                if changeTopologyAfterFirstRead && rootListReads > 1 { children.append("new-anchor") }
            }
            output = children.map { "  \($0)\n" }.joined()
        }
        else if arguments.count == 4, arguments[0] == "-a", arguments.suffix(2) == ["-s", "rules"] { output = anchorContents[arguments[1]] ?? "" }
        else if arguments.contains("-n") { return CommandResult(code: compileExitCode, output: input ?? "", error: compileDiagnostics) }
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
        return CommandResult(code: 0, output: output, error: arguments.contains("-s") ? "No ALTQ support in kernel\nALTQ related functions disabled\n" : "")
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
    func testFreshStartDoesNotReadRulesFromNonexistentOwnedAnchor() async throws {
        let pf = FakePF(), store = MemoryJournal()
        let result = try await request(engine(pf, store), "start")
        XCTAssertEqual(result.phase, .protected, result.message)
        XCTAssertNotNil(store.value)
    }
    func testQuitWithoutJournalOrOwnedAnchorAcknowledgesInactiveWithoutMutation() async throws {
        for action in ["stop", "uninstall"] {
            let pf = FakePF(), store = MemoryJournal()
            let result = try await request(engine(pf, store), action)
            XCTAssertEqual(result.phase, .inactive, result.message)
            XCTAssertTrue(store.removed)
            XCTAssertTrue(pf.mutations.isEmpty)
            XCTAssertFalse(pf.requests.contains(["-a", GuardIdentity.anchor, "-s", "rules"]))
        }
    }
    func testQuitWithoutAppleParentAnchorAcknowledgesInactive() async throws {
        let pf = FakePF(), store = MemoryJournal()
        pf.anchorListings[""] = []
        let result = try await request(engine(pf, store), "stop")
        XCTAssertEqual(result.phase, .inactive, result.message)
        XCTAssertTrue(pf.mutations.isEmpty)
        XCTAssertFalse(pf.requests.contains(["-a", "com.apple", "-s", "Anchors"]))
    }
    func testUnjournaledOwnedRulesRemainUntouched() async throws {
        let pf = FakePF(), store = MemoryJournal()
        pf.rules = "block drop quick all\n"
        let result = try await request(engine(pf, store), "stop")
        XCTAssertEqual(result.phase, .fault)
        XCTAssertFalse(store.removed)
        XCTAssertTrue(pf.mutations.isEmpty)
    }
    func testPresentOwnedAnchorReadErrorStillPreventsRestore() async throws {
        let pf = FakePF(), store = MemoryJournal()
        pf.anchorListings["com.apple", default: []].append(GuardIdentity.anchor)
        pf.readDiagnosticArguments = ["-a", GuardIdentity.anchor, "-s", "rules"]
        let result = try await request(engine(pf, store), "stop")
        XCTAssertEqual(result.phase, .fault)
        XCTAssertFalse(store.removed)
        XCTAssertTrue(pf.mutations.isEmpty)
    }
    func testUncertainAnchorAbsenceDoesNotAcknowledgeRestore() async throws {
        for args in [["-s", "Anchors"], ["-a", "com.apple", "-s", "Anchors"]] {
            let pf = FakePF(), store = MemoryJournal()
            pf.readDiagnosticArguments = args
            let result = try await request(engine(pf, store), "stop")
            XCTAssertEqual(result.phase, .fault)
            XCTAssertFalse(store.removed)
            XCTAssertTrue(pf.mutations.isEmpty)
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
    func testInitialStartRequiresConfirmedHelperVPNEvidenceBeforeAnyMutation() async throws {
        for evidence in [GuardVPNState.unconfirmed, .disconnected] {
            let pf = FakePF(), store = MemoryJournal(), vpn = FakeVPN()
            vpn.connection = evidence
            let result = try await request(engine(pf, store, vpn), "start")
            XCTAssertEqual(result.phase, .fault, "Unexpected activation for \(evidence)")
            XCTAssertTrue(pf.mutations.isEmpty, "PF changed with \(evidence) VPN evidence")
            XCTAssertFalse(pf.enabled)
            XCTAssertNil(store.value, "A journal was created before confirming the VPN")
            XCTAssertFalse(store.removed)
        }
    }
    func testCompetingNestedFilterRulesRefuseBeforeAnyMutation() async throws {
        let pf = FakePF(), store = MemoryJournal()
        pf.anchorListings["com.apple/200.AirDrop"] = ["com.apple/200.AirDrop/nested"]
        pf.anchorContents["com.apple/200.AirDrop/nested"] = "pass quick all\n"
        let result = try await request(engine(pf, store), "start")
        XCTAssertEqual(result.phase, .fault)
        XCTAssertTrue(pf.mutations.isEmpty)
        XCTAssertNil(store.value)
    }
    func testUnexpectedCompilerDiagnosticRefusesBeforeAnyMutation() async throws {
        let pf = FakePF(), store = MemoryJournal()
        pf.compileDiagnostics += "pfctl: syntax error\n"
        let result = try await request(engine(pf, store), "start")
        XCTAssertEqual(result.phase, .fault)
        XCTAssertTrue(pf.mutations.isEmpty)
        XCTAssertNil(store.value)
    }
    func testNewSiblingFilterRulesPreventRestoreWithoutRemovingOwnedRules() async throws {
        let pf = FakePF(), store = MemoryJournal(), guardEngine = engine(pf, store)
        let active = try await request(guardEngine, "start")
        XCTAssertEqual(active.phase, .protected, active.message)
        pf.anchorContents["com.apple/250.ApplicationFirewall"] = "pass quick all\n"
        let result = try await request(guardEngine, "stop")
        XCTAssertEqual(result.phase, .fault)
        XCTAssertTrue(pf.rules.contains("mamori-default-deny"))
        XCTAssertFalse(pf.mutations.contains { $0.contains("-F") || $0.contains("-X") })
        XCTAssertNotNil(store.value)
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

final class PFRuleInspectorTests: XCTestCase {
    func testOwnedAnchorCanBePresentButEmpty() throws {
        let pf = FakePF()
        pf.anchorListings["com.apple", default: []].append(GuardIdentity.anchor)
        XCTAssertEqual(try PFRuleInspector(commands: pf).readOwnedRules(), "")
        XCTAssertTrue(pf.requests.contains(["-a", GuardIdentity.anchor, "-s", "rules"]))
        XCTAssertTrue(pf.mutations.isEmpty)
    }
    func testOwnedAnchorAbsenceRejectsTopologyChanges() {
        let pf = FakePF()
        pf.changeTopologyAfterFirstRead = true
        XCTAssertThrowsError(try PFRuleInspector(commands: pf).readOwnedRules())
        XCTAssertTrue(pf.mutations.isEmpty)
    }
    func testInspectionFailureReportsCommandExitStatusAndDiagnostic() {
        let pf = FakePF()
        let arguments = ["-a", GuardIdentity.anchor, "-s", "rules"]
        pf.readDiagnosticArguments = arguments
        XCTAssertThrowsError(try pf.pfRead(arguments)) { error in
            XCTAssertTrue(error.localizedDescription.contains("pfctl -a com.apple/000.mamori -s rules (exit 0)"))
            XCTAssertTrue(error.localizedDescription.contains("DIOCGETRULES: Invalid argument"))
        }
    }
    func testActualHostHierarchyAvoidsBrokenWildcardPrinter() throws {
        let pf = FakePF()
        pf.root = "scrub-anchor \"com.apple/*\" all fragment reassemble\nanchor \"com.apple/*\" all\n"
        pf.rules = try GuardPolicy.render(.init(tunnelInterface: "utun9", gatewayAddresses: ["203.0.113.4"]), tunnelAllowed: true)
        let snapshot = try PFRuleInspector(commands: pf).read()
        XCTAssertEqual(snapshot.rootRules, pf.root)
        XCTAssertEqual(snapshot.anchorRules[GuardIdentity.anchor], pf.rules)
        XCTAssertEqual(Set(snapshot.anchorRules.keys), ["com.apple", "com.apple/000.mamori", "com.apple/200.AirDrop", "com.apple/250.ApplicationFirewall"])
        XCTAssertTrue(GuardPolicy.containsOnlyOwnedFilterRules(snapshot.anchorRules, expectedOwnRules: pf.rules))
        XCTAssertFalse(pf.requests.contains { $0.contains("*") })
        XCTAssertTrue(pf.mutations.isEmpty)
    }
    func testExitZeroDiagnosticsNeverCountAsSuccessfulInspection() throws {
        for args in [["-s", "rules"], ["-s", "Anchors"], ["-a", "com.apple/200.AirDrop", "-s", "rules"]] {
            let pf = FakePF()
            pf.readDiagnosticArguments = args
            XCTAssertThrowsError(try PFRuleInspector(commands: pf).read(), args.joined(separator: " "))
            XCTAssertTrue(pf.mutations.isEmpty)
        }
        let pf = FakePF()
        // The prior recursive operation's success status must not hide its stderr error.
        XCTAssertThrowsError(try pf.pfRead(["-a", "*", "-s", "rules"]))
    }
    func testUnexpectedTraversalAndDuplicatePathsAreRejected() {
        for listing in [["com.apple"], ["000.mamori"], ["com.apple/*"], ["com.apple/../other"],
                        ["com.apple/child/grandchild"], ["elsewhere/child"],
                        ["com.apple/child", "com.apple/child"]] {
            let pf = FakePF()
            pf.anchorListings["com.apple"] = listing
            XCTAssertThrowsError(try PFRuleInspector(commands: pf).read(), listing.joined(separator: ", "))
            XCTAssertTrue(pf.mutations.isEmpty)
        }
    }
    func testTraversalLimitsAndTopologyChangesAreRejected() {
        let wide = FakePF()
        wide.anchorListings["com.apple"] = (0...64).map { "com.apple/child\($0)" }
        XCTAssertThrowsError(try PFRuleInspector(commands: wide).read())
        let deep = FakePF()
        var parent = "com.apple"
        for _ in 0..<8 {
            let child = parent + "/nested"
            deep.anchorListings[parent] = [child]
            parent = child
        }
        XCTAssertThrowsError(try PFRuleInspector(commands: deep).read())
        let changing = FakePF()
        changing.changeTopologyAfterFirstRead = true
        XCTAssertThrowsError(try PFRuleInspector(commands: changing).read())
    }
}

final class PFPolicyCompilerTests: XCTestCase {
    func testDryRunAcceptsExactPlatformAdvisoryWithMandatoryNoActionFlag() throws {
        let pf = FakePF(), source = "block drop quick all label \"mamori-default-deny\"\n"
        let advisory = pf.compileDiagnostics
        let altq = "No ALTQ support in kernel\nALTQ related functions disabled\n"
        for diagnostics in ["", altq, advisory, altq + advisory, advisory + altq] {
            pf.compileDiagnostics = diagnostics
            XCTAssertEqual(try pf.pfCompilePolicy(source), source)
            XCTAssertEqual(pf.requests.last, ["-a", GuardIdentity.anchor, "-o", "none", "-n", "-v", "-f", "-"])
        }
        XCTAssertTrue(pf.mutations.isEmpty)
    }
    func testUnknownAndFailureDiagnosticsRemainRejected() {
        let pf = FakePF(), advisory = pf.compileDiagnostics
        for diagnostics in [advisory + "pfctl: syntax error\n", "pfctl: DIOCGETRULES: Invalid argument\n", "See /etc/pf.conf for further details.\n"] {
            pf.compileDiagnostics = diagnostics
            XCTAssertThrowsError(try pf.pfCompilePolicy("fixture"))
        }
        pf.compileDiagnostics = advisory
        pf.compileExitCode = 1
        XCTAssertThrowsError(try pf.pfCompilePolicy("fixture"))
        XCTAssertTrue(pf.mutations.isEmpty)
    }
    func testRealReadbackDoesNotAcceptTheDryRunAdvisory() {
        let pf = FakePF()
        pf.readDiagnosticArguments = ["-s", "rules"]
        pf.readDiagnostic = pf.compileDiagnostics
        XCTAssertThrowsError(try pf.pfRead(["-s", "rules"]))
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
