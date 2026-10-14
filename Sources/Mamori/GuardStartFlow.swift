import MamoriCore

/// A fresh helper discovery belongs to every activation attempt. Cancellation
/// is checked again after discovery so Quit cannot be followed by a late start.
@MainActor
enum GuardStartFlow {
    enum Outcome: Equatable {
        case cancelled
        case discoveryFailed(String)
        case activated(GuardStatus)
    }

    static func run(
        discover: () async -> GuardDiscovery,
        activate: (GuardConfiguration) async -> GuardStatus,
        isCurrent: () -> Bool
    ) async -> Outcome {
        guard isCurrent() else { return .cancelled }
        let discovery = await discover()
        guard isCurrent() else { return .cancelled }
        guard let configuration = discovery.configuration else {
            return .discoveryFailed(discovery.message)
        }
        return .activated(await activate(configuration))
    }
}
