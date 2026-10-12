import Darwin
import Foundation
import Security
import SystemConfiguration
import MamoriCore

protocol GuardVPNVerifying: Sendable {
    func discover() -> GuardDiscovery
    func state(for configuration: GuardConfiguration, requireEndpoints: Bool) -> GuardVPNState
}

struct GlobalProtectVerifier: GuardVPNVerifying {
    let commands: any GuardCommandRunning
    init(commands: any GuardCommandRunning = ProcessCommandRunner()) { self.commands = commands }

    func discover() -> GuardDiscovery {
        do {
            guard let pid = try trustedPID() else { return GuardDiscovery(message: "Connect GlobalProtect before detecting its configuration.") }
            let interfaces = try ownedActiveInterfaces()
            guard interfaces.count == 1, let interface = interfaces.first else {
                return GuardDiscovery(message: "A single active GlobalProtect-owned tunnel could not be identified. Connect GlobalProtect and retry.")
            }
            let configuration = GuardConfiguration(tunnelInterface: interface, gatewayAddresses: try endpoints(pid: pid))
            try GuardPolicy.validate(configuration)
            guard state(for: configuration, requireEndpoints: true) == .connected else { return GuardDiscovery(message: "The detected tunnel and gateway could not be confirmed together. Retry after GlobalProtect connects.") }
            return GuardDiscovery(configuration: configuration, message: "Detected the active GlobalProtect tunnel and IPv4 transport endpoints. Review these before starting protection.")
        } catch {
            // Never log raw lsof output, addresses, hostnames, or company connection data.
            return GuardDiscovery(message: error.localizedDescription)
        }
    }

    func state(for configuration: GuardConfiguration, requireEndpoints: Bool) -> GuardVPNState {
        do {
            guard let pid = try trustedPID() else { return .disconnected }
            let interfaces = try ownedActiveInterfaces()
            let interfaceState = Self.classify(interfaces: interfaces, selected: configuration.tunnelInterface)
            guard interfaceState == .connected else { return interfaceState }
            // Sampled destinations do not prove full-tunnel coverage. The PF policy blocks
            // physical fallback independently; these checks reject a changed selected route.
            for destination in ["1.1.1.1", "208.67.222.222"] {
                let route = try commands.run("/sbin/route", ["-n", "get", destination])
                guard route.code == 0 else { return .unconfirmed }
                let records = route.output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                guard let selected = records.first(where: { $0.hasPrefix("interface: ") }) else { return .unconfirmed }
                guard selected == "interface: \(configuration.tunnelInterface)" else { return .disconnected }
            }
            if requireEndpoints {
                let observed = try endpoints(pid: pid)
                guard !observed.isEmpty, Set(observed).isSubset(of: Set(configuration.gatewayAddresses)) else { return .unconfirmed }
            }
            return .connected
        } catch { return .unconfirmed }
    }

    static func classify(interfaces: Set<String>, selected: String) -> GuardVPNState {
        // Gateway transitions can temporarily expose multiple owned tunnels. They are
        // ambiguous evidence: block direct traffic, but do not trigger app termination.
        guard interfaces.count <= 1 else { return .unconfirmed }
        return interfaces.contains(selected) ? .connected : .disconnected
    }

    private func trustedPID() throws -> pid_t? {
        let running = try commands.run("/usr/bin/pgrep", ["-x", "PanGPS"])
        if running.code == 1 { return nil }
        let identifiers = running.output.split(whereSeparator: \.isWhitespace).compactMap { Int32($0) }
        guard running.code == 0, identifiers.count == 1, let pid = identifiers.first, pid > 0 else {
            throw GuardFailure.message("The running GlobalProtect service could not be identified unambiguously.")
        }
        var guest: SecCode?, requirement: SecRequirement?
        let expected = "anchor apple generic and identifier \"PanGPS\" and certificate leaf[subject.OU] = \"PXPZ95SK77\""
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: NSNumber(value: pid)] as CFDictionary, [], &guest) == errSecSuccess, let guest,
              SecRequirementCreateWithString(expected as CFString, [], &requirement) == errSecSuccess,
              SecCodeCheckValidity(guest, [], requirement) == errSecSuccess else {
            throw GuardFailure.message("The running GlobalProtect service's signing identity could not be verified.")
        }
        return pid
    }

    private func endpoints(pid: pid_t) throws -> [String] {
        let result = try commands.run("/usr/sbin/lsof", ["-nP", "-a", "-p", String(pid), "-i", "-Fn"])
        guard result.code == 0 else { throw GuardFailure.message("GlobalProtect's active transport endpoints could not be read.") }
        var addresses = Set<String>()
        for record in result.output.split(separator: "\n") where record.hasPrefix("n") {
            guard let arrow = record.range(of: "->") else { continue }
            let remote = record[arrow.upperBound...].split(whereSeparator: \.isWhitespace).first ?? ""
            guard let colon = remote.lastIndex(of: ":"), ["443", "4501"].contains(String(remote[remote.index(after: colon)...])) else { continue }
            let address = String(remote[..<colon])
            guard !address.contains(":"), !address.contains("[") else { throw GuardFailure.message("This release does not support IPv6 GlobalProtect transport endpoints.") }
            addresses.insert(address)
        }
        guard !addresses.isEmpty else { throw GuardFailure.message("No active IPv4 GlobalProtect transport endpoint was found. Connect the VPN and retry.") }
        return addresses.sorted()
    }

    private func ownedActiveInterfaces() throws -> Set<String> {
        guard let store = SCDynamicStoreCreate(nil, "com.mamori.guard.discovery" as CFString, nil, nil),
              let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/.*/IPv[46]" as CFString) as? [String] else {
            throw GuardFailure.message("GlobalProtect's system network records could not be read.")
        }
        var start: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&start) == 0 else { throw GuardFailure.message("Active network interfaces could not be read.") }
        defer { if let start { freeifaddrs(start) } }
        var active: [String: Set<String>] = [:], pointer = start
        while let item = pointer?.pointee {
            pointer = item.ifa_next
            let name = String(cString: item.ifa_name), required = UInt32(IFF_UP | IFF_RUNNING | IFF_POINTOPOINT)
            guard name.hasPrefix("utun"), item.ifa_flags & required == required, let address = item.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) || address.pointee.sa_family == UInt8(AF_INET6) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                active[name, default: []].insert(Self.normalize(String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)))
            }
        }
        var matches = Set<String>()
        for key in keys {
            let components = key.lowercased().split(separator: "/")
            guard components.count >= 5 else { continue }
            let service = String(components[3])
            guard service == "gpd.pan" || service.hasPrefix("com.paloaltonetworks.globalprotect") else { continue }
            guard let record = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any],
                  let interface = record[kSCPropInterfaceName as String] as? String,
                  let addresses = record["Addresses"] as? [String], !addresses.isEmpty else {
                throw GuardFailure.message("A GlobalProtect-owned network record is incomplete.")
            }
            if !(active[interface] ?? []).isDisjoint(with: Set(addresses.map(Self.normalize))) { matches.insert(interface) }
        }
        return matches
    }
    private static func normalize(_ value: String) -> String { String(value.split(separator: "%", maxSplits: 1).first ?? "").lowercased() }
}
