import Foundation

public enum GuardPhase: String, Codable, Sendable {
    case unavailable, inactive, arming, protected, blocked, fault
}

public enum GuardVPNState: String, Codable, Sendable {
    case connected, disconnected, unconfirmed
}

public struct GuardConfiguration: Codable, Equatable, Sendable {
    public var tunnelInterface: String
    public var gatewayAddresses: [String]
    public init(tunnelInterface: String, gatewayAddresses: [String]) {
        self.tunnelInterface = tunnelInterface
        self.gatewayAddresses = gatewayAddresses
    }
}

public struct GuardStatus: Codable, Equatable, Sendable {
    public var phase: GuardPhase
    public var message: String
    public var configuration: GuardConfiguration?
    public var helperAvailable: Bool
    public var vpnState: GuardVPNState?
    public init(phase: GuardPhase, message: String, configuration: GuardConfiguration? = nil, helperAvailable: Bool = false, vpnState: GuardVPNState? = nil) {
        self.phase = phase
        self.message = message
        self.configuration = configuration
        self.helperAvailable = helperAvailable
        self.vpnState = vpnState
    }
    public var isEnforcing: Bool { phase == .protected || phase == .blocked }
}

public struct GuardDiscovery: Codable, Equatable, Sendable {
    public var configuration: GuardConfiguration?
    public var message: String
    public init(configuration: GuardConfiguration? = nil, message: String) {
        self.configuration = configuration
        self.message = message
    }
}

public enum GuardIdentity {
    public static let app = "com.mamori.app"
    public static let service = "com.mamori.guard"
    public static let plist = "com.mamori.guard.plist"
    public static let anchor = "com.apple/000.mamori"
}

/// Fixed, typed operations only. No shell text, arbitrary paths, or process IDs cross XPC.
@objc public protocol GuardXPCProtocol {
    func discoverConfiguration(reply: @escaping @Sendable (Data) -> Void)
    func getStatus(reply: @escaping @Sendable (Data) -> Void)
    func start(configuration: Data, reply: @escaping @Sendable (Data) -> Void)
    func stop(reply: @escaping @Sendable (Data) -> Void)
    func prepareUninstall(reply: @escaping @Sendable (Data) -> Void)
}
