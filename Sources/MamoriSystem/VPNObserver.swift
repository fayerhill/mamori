import AppKit
import Darwin
import Foundation
import MamoriCore
import SystemConfiguration

public enum VPNConnectionState: String, Sendable {
    case connected
    case disconnected
    case unconfirmed
}

public struct VPNSnapshot: Sendable {
    public let state: VPNConnectionState
    public let label: String
    public let interface: String?
    public let evidence: [String]
    public let observedAt: Date
    public var isConnected: Bool { state == .connected }

    public init(
        state: VPNConnectionState,
        label: String,
        interface: String? = nil,
        evidence: [String],
        observedAt: Date = Date()
    ) {
        self.state = state
        self.label = label
        self.interface = interface
        self.evidence = evidence
        self.observedAt = observedAt
    }
}

/// A read-only observer. The caller schedules sampling and decides how to react.
@MainActor
public final class VPNObserver {
    private var previouslyConfirmed = false

    public init() {}

    public func snapshot() -> VPNSnapshot {
        let clientRunning = NSWorkspace.shared.runningApplications.contains {
            Self.isGlobalProtectClient($0.bundleIdentifier) && !$0.isTerminated
        }
        var evidence = [clientRunning ? "GlobalProtect client is running." : "GlobalProtect client is not visible."]
        guard let store = SCDynamicStoreCreate(nil, "com.mamori.vpn-observer" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(
                store, "State:/Network/Service/.*/IPv[46]" as CFString
              ) as? [String] else {
            evidence.append("The system network state could not be read.")
            return VPNSnapshot(state: .unconfirmed, label: "VPN status unavailable", evidence: evidence)
        }

        let ownedKeys = keys.filter(Self.isGlobalProtectKey).sorted()
        guard !ownedKeys.isEmpty else {
            evidence.append("No GlobalProtect-owned IPv4 or IPv6 service was found.")
            let signal = GlobalProtectEvidenceClassifier.classify(
                clientRunning: clientRunning, previouslyConfirmed: previouslyConfirmed, evidence: .absent
            )
            return VPNSnapshot(
                state: signal == .disconnected ? .disconnected : .unconfirmed,
                label: previouslyConfirmed ? "GlobalProtect tunnel disconnected" : "GlobalProtect connection not confirmed",
                evidence: evidence
            )
        }

        guard let interfaces = Self.activeTunnelAddresses() else {
            evidence.append("The current network interfaces could not be read.")
            return VPNSnapshot(state: .unconfirmed, label: "VPN status unavailable", evidence: evidence)
        }
        var matchedInterfaces = Set<String>()
        var malformed = false
        for key in ownedKeys {
            guard let values = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  let interface = values[kSCPropInterfaceName as String] as? String,
                  let assigned = values[kSCPropNetIPv4Addresses as String] as? [String],
                  !assigned.isEmpty else {
                malformed = true
                continue
            }
            let active = interfaces[interface] ?? []
            let normalized = Set(assigned.map(Self.normalizedAddress))
            if !active.isDisjoint(with: normalized) {
                matchedInterfaces.insert(interface)
                evidence.append("GlobalProtect service and active \(interface) interface have matching addresses.")
            } else {
                evidence.append("The GlobalProtect service's interface is inactive or its addresses do not match.")
            }
        }

        let tunnelEvidence: GlobalProtectTunnelEvidence = malformed ? .malformed : matchedInterfaces.isEmpty ? .inactive : .active(interfaces: matchedInterfaces)
        let signal = GlobalProtectEvidenceClassifier.classify(
            clientRunning: clientRunning, previouslyConfirmed: previouslyConfirmed, evidence: tunnelEvidence
        )
        guard signal == .connected, let interface = matchedInterfaces.first else {
            if matchedInterfaces.count > 1 { evidence.append("More than one GlobalProtect tunnel was observed.") }
            if malformed { evidence.append("An owned tunnel record was incomplete or unreadable.") }
            if !clientRunning { evidence.append("A tunnel record alone does not confirm an active GlobalProtect client.") }
            return VPNSnapshot(
                state: signal == .disconnected ? .disconnected : .unconfirmed,
                label: signal == .disconnected ? "GlobalProtect tunnel disconnected" : "VPN connection not confirmed",
                evidence: evidence
            )
        }
        previouslyConfirmed = true
        evidence.append("This confirms local tunnel evidence, not remote reachability or traffic protection.")
        return VPNSnapshot(
            state: .connected,
            label: "GlobalProtect tunnel detected",
            interface: interface,
            evidence: evidence
        )
    }

    /// Advisory client recognition only. The helper independently verifies the signed service.
    nonisolated static func isGlobalProtectClient(_ bundleIdentifier: String?) -> Bool {
        guard let identifier = bundleIdentifier?.lowercased() else { return false }
        return identifier == "com.paloaltonetworks.globalprotect" ||
            identifier == "com.paloaltonetworks.globalprotect.client"
    }

    private static func isGlobalProtectKey(_ key: String) -> Bool {
        let components = key.lowercased().split(separator: "/")
        guard components.count >= 5 else { return false }
        let service = String(components[3])
        return service == "gpd.pan" || service.hasPrefix("com.paloaltonetworks.globalprotect")
    }

    private static func normalizedAddress(_ address: String) -> String {
        address.split(separator: "%", maxSplits: 1).first.map(String.init)?.lowercased() ?? address.lowercased()
    }

    private static func activeTunnelAddresses() -> [String: Set<String>]? {
        var start: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&start) == 0 else { return nil }
        guard let first = start else { return [:] }
        defer { freeifaddrs(start) }
        var result: [String: Set<String>] = [:]
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let item = pointer.pointee
            cursor = item.ifa_next
            let name = String(cString: item.ifa_name)
            let required = UInt32(IFF_UP | IFF_RUNNING | IFF_POINTOPOINT)
            guard name.hasPrefix("utun"), item.ifa_flags & required == required,
                  let address = item.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6) else {
                continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(
                address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                nil, 0, NI_NUMERICHOST
            )
            if status == 0 {
                let bytes = host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
                result[name, default: []].insert(normalizedAddress(String(decoding: bytes, as: UTF8.self)))
            }
        }
        return result
    }
}
