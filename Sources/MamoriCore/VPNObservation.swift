import Foundation

/// Already inspected, local evidence. No case implies remote reachability.
public enum GlobalProtectTunnelEvidence: Equatable, Sendable {
    case unreadable
    case absent
    case malformed
    case inactive
    case active(interfaces: Set<String>)
}

public enum GlobalProtectEvidenceClassifier {
    public static func classify(
        clientRunning: Bool,
        previouslyConfirmed: Bool,
        evidence: GlobalProtectTunnelEvidence
    ) -> VPNConnectionSignal {
        switch evidence {
        case .unreadable, .malformed:
            return .unverified
        case .absent:
            return previouslyConfirmed || !clientRunning ? .disconnected : .unverified
        case .inactive:
            return previouslyConfirmed ? .disconnected : .unverified
        case .active(let interfaces):
            return clientRunning && interfaces.count == 1 ? .connected : .unverified
        }
    }
}
