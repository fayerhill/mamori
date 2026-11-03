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
        XCTAssertNil(policy.range(of: #"port 53\b"#, options: .regularExpression))
        XCTAssertTrue(policy.contains("to { 203.0.113.4 } port 443"))
        XCTAssertTrue(policy.contains("to { 203.0.113.4 } port 4501"))
    }
    func testLocalDeviceRulesRequireLocalAddressesAtBothEndsInEveryVPNState() throws {
        for tunnelAllowed in [true, false] {
            let lines = GuardPolicy.meaningfulLines(try GuardPolicy.render(configuration, tunnelAllowed: tunnelAllowed))
            let local = lines.filter { $0.contains("label \"mamori-local-") }
            XCTAssertEqual(local, [
                "pass quick inet from { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 } to { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 } flags any no state label \"mamori-local-ipv4\"",
                "pass quick inet6 from { fe80::/10, fc00::/7 } to { fe80::/10, fc00::/7 } flags any no state label \"mamori-local-ipv6\""
            ])
            // No interface snapshot: AirDrop/USB links may appear after activation.
            XCTAssertFalse(local.contains { $0.contains(" on ") })
            XCTAssertTrue(local.allSatisfy { lines.firstIndex(of: $0)! < lines.count - 1 })
        }
    }
    func testBonjourAndIPv6DiscoveryExceptionsAreLimitedToLinkLocalMulticast() throws {
        let lines = GuardPolicy.meaningfulLines(try GuardPolicy.render(configuration, tunnelAllowed: false))
        let mdns = lines.filter { $0.contains("label \"mamori-mdns-") }
        XCTAssertEqual(mdns.count, 2)
        XCTAssertTrue(mdns[0].contains("inet proto udp from { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 } to 224.0.0.251 port 5353 no state"))
        XCTAssertTrue(mdns[1].contains("inet6 proto udp from { fe80::/10, fc00::/7 } to ff02::fb port 5353 no state"))
        let discovery = lines.filter { $0.contains("label \"mamori-ipv6-discovery\"") }
        XCTAssertEqual(discovery, ["pass quick inet6 proto icmp6 from { ::/128, fe80::/10 } to ff02::/16 icmp6-type { 130, 131, 132, 133, 134, 135, 136, 143 } no state label \"mamori-ipv6-discovery\""])
        XCTAssertFalse(lines.contains { $0.contains("224.0.0.0/4") || $0.contains("ff00::/8") })
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
        let anchors = ["com.apple": "anchor \"200.AirDrop/*\" all\n", "com.apple/200.AirDrop": ""]
        XCTAssertNoThrow(try GuardPolicy.preflight(rootRules: root, anchorRules: anchors, pfEnabled: false, stateCount: 0))
        XCTAssertThrowsError(try GuardPolicy.preflight(rootRules: root, anchorRules: anchors, pfEnabled: false, stateCount: 1))
        XCTAssertThrowsError(try GuardPolicy.preflight(rootRules: root, anchorRules: anchors, pfEnabled: true, stateCount: 0))
        XCTAssertThrowsError(try GuardPolicy.preflight(rootRules: "pass quick all\n" + root, anchorRules: anchors, pfEnabled: false, stateCount: 0))
        XCTAssertThrowsError(try GuardPolicy.preflight(rootRules: root, anchorRules: ["com.apple": "pass all\n"], pfEnabled: false, stateCount: 0))
        let stockScrub = "scrub-anchor \"com.apple/*\" all fragment reassemble\n"
        XCTAssertNoThrow(try GuardPolicy.preflight(rootRules: stockScrub + root, anchorRules: anchors, pfEnabled: false, stateCount: 0))
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
        var anchors = ["com.apple": "anchor \"200.AirDrop/*\" all\n", "com.apple/200.AirDrop": "", GuardIdentity.anchor: rules]
        XCTAssertTrue(GuardPolicy.containsOnlyOwnedFilterRules(anchors, expectedOwnRules: rules))
        anchors["com.apple/200.AirDrop"] = "pass quick all\n"
        XCTAssertFalse(GuardPolicy.containsOnlyOwnedFilterRules(anchors, expectedOwnRules: rules))
    }
    func testConcreteReadbackNeverDeduplicatesReordersOrIgnoresNestedForeignRules() throws {
        let rules = try GuardPolicy.render(configuration, tunnelAllowed: true)
        let valid = ["com.apple": "", GuardIdentity.anchor: rules]
        for changed in [rules + "pass quick all\n", rules + rules, GuardPolicy.meaningfulLines(rules).reversed().joined(separator: "\n")] {
            var anchors = valid
            anchors[GuardIdentity.anchor] = changed
            XCTAssertFalse(GuardPolicy.containsOnlyOwnedFilterRules(anchors, expectedOwnRules: rules))
        }
        for (path, content) in [
            (GuardIdentity.anchor + "/hidden", ""),
            ("com.apple/200.AirDrop/nested", "pass quick all"),
            ("com.apple/200.AirDrop", "anchor \"elsewhere\" quick all"),
            ("com.apple/200.AirDrop", "anchor \"../000.mamori\" all"),
            ("com.apple/200.AirDrop", "anchor \"*\" all {\n}")
        ] {
            var anchors = valid
            anchors[path] = content
            XCTAssertFalse(GuardPolicy.containsOnlyOwnedFilterRules(anchors, expectedOwnRules: rules), path)
        }
        XCTAssertFalse(GuardPolicy.containsOnlyOwnedFilterRules(["com.apple": ""], expectedOwnRules: rules))
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
