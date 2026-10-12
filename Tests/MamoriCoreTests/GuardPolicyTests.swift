import XCTest
@testable import MamoriCore

final class GuardPolicyTests: XCTestCase {
    let configuration = GuardConfiguration(tunnelInterface: "utun9", gatewayAddresses: ["203.0.113.4"])

    func testUnknownInterfacesAndBothIPFamiliesDefaultToDeny() throws {
        let policy = try GuardPolicy.render(configuration, tunnelAllowed: true)
        XCTAssertTrue(policy.hasSuffix("block drop quick all label \"mamori-default-deny\"\n"))
        XCTAssertFalse(policy.contains("keep state"))
        XCTAssertFalse(policy.contains("on en0"))
        XCTAssertTrue(policy.contains("pass quick on utun9 all flags any no state"))
    }
    func testDisconnectedPolicyDoesNotAllowAnyTunnelOrGeneralDNS() throws {
        let policy = try GuardPolicy.render(configuration, tunnelAllowed: false)
        XCTAssertFalse(policy.contains("utun"))
        XCTAssertFalse(policy.contains("port 53"))
        XCTAssertTrue(policy.contains("to { 203.0.113.4 } port 443"))
        XCTAssertTrue(policy.contains("to { 203.0.113.4 } port 4501"))
    }
    func testConfigurationCannotInjectPFRules() {
        for tunnel in ["en0", "utun9\n", "utun9\npass all", "utun*", "utun", "utun00000"] {
            XCTAssertThrowsError(try GuardPolicy.validate(.init(tunnelInterface: tunnel, gatewayAddresses: ["203.0.113.4"])))
        }
        for gateway in ["any", "vpn.example.com", "203.0.113.4/0", "203.0.113.4\npass all", "::1", "127.0.0.1", "10.1.2.3", "224.0.0.1"] {
            XCTAssertThrowsError(try GuardPolicy.validate(.init(tunnelInterface: "utun9", gatewayAddresses: [gateway])))
        }
    }
    func testPreflightRejectsStateBypassAndCompetingFirewall() throws {
        let root = "anchor \"com.apple/*\" all\n"
        let recursive = "anchor \"com.apple/*\" all {\n}\n"
        XCTAssertNoThrow(try GuardPolicy.preflight(rootRules: root, recursiveRules: recursive, pfEnabled: false, stateCount: 0))
        XCTAssertThrowsError(try GuardPolicy.preflight(rootRules: root, recursiveRules: recursive, pfEnabled: false, stateCount: 1))
        XCTAssertThrowsError(try GuardPolicy.preflight(rootRules: root, recursiveRules: recursive, pfEnabled: true, stateCount: 0))
        XCTAssertThrowsError(try GuardPolicy.preflight(rootRules: "pass quick all\n" + root, recursiveRules: recursive, pfEnabled: false, stateCount: 0))
        XCTAssertThrowsError(try GuardPolicy.preflight(rootRules: root, recursiveRules: recursive + "pass all\n", pfEnabled: false, stateCount: 0))
        let stockScrub = "scrub-anchor \"com.apple/*\" all fragment reassemble\n"
        XCTAssertNoThrow(try GuardPolicy.preflight(rootRules: stockScrub + root, recursiveRules: stockScrub + recursive, pfEnabled: false, stateCount: 0))
    }

    func testPlatformNormalizedNoStatePolicyIsAcceptedWithoutWeakLabelOnlyMatching() throws {
        // Captured from a non-mutating macOS pfctl -n -v parser invocation.
        let normalized = """
        pass quick on lo0 all no state label "mamori-loopback"
        pass out quick inet proto udp from any port = 68 to 255.255.255.255 port = 67 no state label "mamori-dhcp-out"
        pass in quick inet proto udp from any port = 67 to any port = 68 no state label "mamori-dhcp-in"
        pass out quick inet proto tcp from any to 203.0.113.4 port = 443 no state label "mamori-vpn-tcp-out"
        pass in quick inet proto tcp from 203.0.113.4 port = 443 to any no state label "mamori-vpn-tcp-in"
        pass out quick inet proto udp from any to 203.0.113.4 port = 4501 no state label "mamori-vpn-udp-out"
        pass in quick inet proto udp from 203.0.113.4 port = 4501 to any no state label "mamori-vpn-udp-in"
        pass quick on utun9 all no state label "mamori-tunnel"
        block drop quick all label "mamori-default-deny"
        """
        XCTAssertTrue(GuardPolicy.validCompiledPolicy(normalized, tunnelAllowed: true))
        XCTAssertFalse(GuardPolicy.rulesMatch(normalized + "\npass quick all", normalized))
        XCTAssertFalse(GuardPolicy.rulesMatch(normalized.replacingOccurrences(of: "203.0.113.4", with: "any"), normalized))
    }
    func testNewSiblingPassRuleInvalidatesEnforcement() throws {
        let rules = try GuardPolicy.render(configuration, tunnelAllowed: true)
        let nested = "anchor \"com.apple/*\" all {\nanchor \"000.mamori\" all {\n" + rules + "}\n}\n"
        XCTAssertTrue(GuardPolicy.containsOnlyOwnedFilterRules(nested, expectedOwnRules: rules))
        XCTAssertFalse(GuardPolicy.containsOnlyOwnedFilterRules(nested + "pass quick all\n", expectedOwnRules: rules))
    }
    func testUnavailableHelperCannotErasePendingRestoration() {
        XCTAssertTrue(GuardPolicy.restorationRequired(previouslyPending: true, confirmedPhase: .unavailable))
        XCTAssertTrue(GuardPolicy.restorationRequired(previouslyPending: true, confirmedPhase: nil))
        XCTAssertTrue(GuardPolicy.restorationRequired(previouslyPending: false, confirmedPhase: .fault))
        XCTAssertFalse(GuardPolicy.restorationRequired(previouslyPending: true, confirmedPhase: .inactive))
    }
    func testStoppedJournalCannotResumeAfterCrash() {
        XCTAssertFalse(GuardPolicy.mayResumeProtection(desiredArmed: false, token: "123", rulesMatch: true))
        XCTAssertFalse(GuardPolicy.mayResumeProtection(desiredArmed: true, token: nil, rulesMatch: true))
        XCTAssertFalse(GuardPolicy.mayResumeProtection(desiredArmed: true, token: "123", rulesMatch: false))
        XCTAssertTrue(GuardPolicy.mayResumeProtection(desiredArmed: true, token: "123", rulesMatch: true))
    }
    func testJournalRetainsOwnershipAndStopIntent() throws {
        let original = GuardJournal(configuration: configuration, ownerUID: 501, desiredArmed: false, token: "456", expectedRules: "owned", rootRules: "untouched")
        let recovered = try JSONDecoder().decode(GuardJournal.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(recovered, original)
        XCTAssertFalse(recovered.desiredArmed)
    }
}
