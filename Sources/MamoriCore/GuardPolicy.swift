import Foundation
import Darwin

public enum GuardPolicyError: Error, LocalizedError, Equatable {
    case invalidTunnel, invalidGateway, noGateway, unsupportedPF, existingStates, alreadyEnabled, competingRules
    public var errorDescription: String? {
        switch self {
        case .invalidTunnel: "Select a specific utun interface, such as utun9."
        case .invalidGateway: "The first release accepts literal, public IPv4 VPN gateway addresses only."
        case .noGateway: "Add at least one confirmed GlobalProtect gateway address."
        case .unsupportedPF: "The stock Apple PF filter anchor is unavailable. Mamori will not rewrite the main firewall configuration."
        case .existingStates: "Existing PF states could bypass protection. Mamori will not flush other software's connections."
        case .alreadyEnabled: "PF is already enabled by another component. This minimal release requires an otherwise inactive PF firewall."
        case .competingRules: "Other active PF filter rules were found. Mamori cannot safely combine this configuration."
        }
    }
}

public enum GuardPolicy {
    public static func validate(_ configuration: GuardConfiguration) throws {
        guard configuration.tunnelInterface.range(of: #"\Autun[0-9]{1,4}\z"#, options: .regularExpression) != nil else { throw GuardPolicyError.invalidTunnel }
        guard !configuration.gatewayAddresses.isEmpty, configuration.gatewayAddresses.count <= 8 else { throw GuardPolicyError.noGateway }
        for address in configuration.gatewayAddresses {
            var storage = in_addr()
            guard address.withCString({ inet_pton(AF_INET, $0, &storage) }) == 1 else { throw GuardPolicyError.invalidGateway }
            let bytes = address.split(separator: ".").compactMap { Int($0) }
            guard bytes.count == 4, bytes[0] > 0, bytes[0] < 224,
                  bytes[0] != 127, bytes[0] != 10,
                  !(bytes[0] == 169 && bytes[1] == 254),
                  !(bytes[0] == 172 && (16...31).contains(bytes[1])),
                  !(bytes[0] == 192 && bytes[1] == 168),
                  !(bytes[0] == 100 && (64...127).contains(bytes[1])) else { throw GuardPolicyError.invalidGateway }
        }
    }

    /// The default block covers every interface and both IP families, including new interfaces.
    /// No state is created: a tunnel flow must never become a floating physical-interface pass.
    public static func render(_ configuration: GuardConfiguration, tunnelAllowed: Bool) throws -> String {
        try validate(configuration)
        let gateways = Array(Set(configuration.gatewayAddresses)).sorted().joined(separator: ", ")
        var rules = [
            "pass quick on lo0 all no state label \"mamori-loopback\"",
            "pass out quick inet proto udp from any port 68 to 255.255.255.255 port 67 no state label \"mamori-dhcp-out\"",
            "pass in quick inet proto udp from any port 67 to any port 68 no state label \"mamori-dhcp-in\"",
            "pass out quick inet proto tcp to { \(gateways) } port 443 flags any no state label \"mamori-vpn-tcp-out\"",
            "pass in quick inet proto tcp from { \(gateways) } port 443 flags any no state label \"mamori-vpn-tcp-in\"",
            "pass out quick inet proto udp to { \(gateways) } port 4501 no state label \"mamori-vpn-udp-out\"",
            "pass in quick inet proto udp from { \(gateways) } port 4501 no state label \"mamori-vpn-udp-in\""
        ]
        if tunnelAllowed { rules.append("pass quick on \(configuration.tunnelInterface) all no state label \"mamori-tunnel\"") }
        rules.append("block drop quick all label \"mamori-default-deny\"")
        return rules.joined(separator: "\n") + "\n"
    }

    public static func preflight(rootRules: String, recursiveRules: String, pfEnabled: Bool, stateCount: Int) throws {
        guard !pfEnabled else { throw GuardPolicyError.alreadyEnabled }
        guard stateCount == 0 else { throw GuardPolicyError.existingStates }
        let root = meaningfulLines(rootRules)
        guard root.count == 1, root[0] == "anchor \"com.apple/*\" all" else { throw GuardPolicyError.unsupportedPF }
        guard meaningfulLines(recursiveRules).allSatisfy({ line in
            line == "}" || line.hasPrefix("anchor \"")
        }) else { throw GuardPolicyError.competingRules }
    }

    public static func meaningfulLines(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    public static func containsOnlyOwnedFilterRules(_ recursiveRules: String, expectedOwnRules: String) -> Bool {
        let active = meaningfulLines(recursiveRules).filter { $0 != "}" && !$0.hasPrefix("anchor \"") }
        return active.sorted() == meaningfulLines(expectedOwnRules).sorted()
    }

    /// Only an authenticated helper's inactive acknowledgment clears pending restoration.
    public static func restorationRequired(previouslyPending: Bool, confirmedPhase: GuardPhase?) -> Bool {
        guard let confirmedPhase else { return true }
        switch confirmedPhase {
        case .inactive: return false
        case .protected, .blocked, .arming, .fault: return true
        case .unavailable: return previouslyPending
        }
    }

    /// A persisted stop intent suppresses automatic re-arming after a helper restart.
    public static func mayResumeProtection(desiredArmed: Bool, token: String?, rulesMatch: Bool) -> Bool {
        desiredArmed && token?.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil && rulesMatch
    }
}

public struct GuardJournal: Codable, Equatable, Sendable {
    public var configuration: GuardConfiguration
    public var ownerUID: UInt32
    public var desiredArmed: Bool
    public var token: String?
    public var enableRequested: Bool
    public var expectedRules: String
    public var rootRules: String
    public init(configuration: GuardConfiguration, ownerUID: UInt32, desiredArmed: Bool = true, token: String? = nil, enableRequested: Bool = false, expectedRules: String = "", rootRules: String) {
        self.configuration = configuration
        self.ownerUID = ownerUID
        self.desiredArmed = desiredArmed
        self.token = token
        self.enableRequested = enableRequested
        self.expectedRules = expectedRules
        self.rootRules = rootRules
    }
}
