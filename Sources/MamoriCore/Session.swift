import Foundation

public enum SessionPhase: String, Equatable, Sendable {
    case idle, arming, protected, blocked, fault, restoring
}

/// Connected and disconnected must be confirmed by the current VPN observer.
/// An interface name or an inconclusive observation is only unverified evidence.
public enum VPNConnectionSignal: Equatable, Sendable {
    case connected, disconnected, unverified
}

public enum GuardActivationResult: Equatable, Sendable {
    case verified(VPNConnectionSignal)
    case failed(String)
}

public enum KeepAwakeChoice: Equatable, Sendable {
    case off
    case whileAppRuns
    case forDuration(seconds: TimeInterval)
}

public enum SessionEvent: Equatable, Sendable {
    case startGuard
    case guardActivationCompleted(operation: UInt64, result: GuardActivationResult)
    case vpnChanged(VPNConnectionSignal)
    case backendFailed(String)
    case existingGuardNeedsRestoration(String)
    case setAutoQuit(Bool)
    case setSelectedApplications(Set<String>)
    case applicationDidQuit(id: String, ticket: UInt64)
    case stopGuard
    case normalQuit
    case retryRestoration
    case restorationCompleted(operation: UInt64, success: Bool, message: String?)
    case setKeepAwake(KeepAwakeChoice)
    case wakeAcquisitionCompleted(ticket: UInt64, success: Bool)
    case wakeDurationElapsed(ticket: UInt64)
}

public enum SessionEffect: Equatable, Sendable {
    case activateGuard(operation: UInt64)
    case restoreGuard(operation: UInt64)
    case quitApplications(ids: [String], ticket: UInt64)
    case cancelApplicationQuits(ids: [String])
    case acquireWake(ticket: UInt64)
    case releaseWake(ticket: UInt64)
    case scheduleWakeTimeout(ticket: UInt64, seconds: TimeInterval)
    case cancelWakeTimeout
    case exitApplication
}

/// Pure state. The platform adapter executes effects and sends completions back.
public struct SessionState: Equatable, Sendable {
    public fileprivate(set) var phase: SessionPhase = .idle
    public fileprivate(set) var vpn: VPNConnectionSignal = .unverified
    public fileprivate(set) var autoQuitEnabled = false
    public fileprivate(set) var selectedApplicationIDs: Set<String> = []
    public fileprivate(set) var pendingApplicationIDs: Set<String> = []
    public fileprivate(set) var autoQuitTicket: UInt64 = 0
    public fileprivate(set) var guardOperation: UInt64 = 0
    public fileprivate(set) var keepAwake: KeepAwakeChoice = .off
    public fileprivate(set) var wakeTicket: UInt64 = 0
    public fileprivate(set) var wakeActive = false
    public fileprivate(set) var wakeAcquiring = false
    public fileprivate(set) var errorMessage: String?
    public fileprivate(set) var wantsToQuit = false

    fileprivate var activationInFlight: UInt64?
    fileprivate var needsRestoration = false
    fileprivate var lastConfirmedConnected = false
    fileprivate var autoQuitArmed = false

    public init() {}

    /// Recheck immediately before both graceful quit and delayed force quit.
    /// The adapter must additionally revalidate the selected app's identity.
    public func canPerformAutoQuit(id: String, ticket: UInt64) -> Bool {
        ticket == autoQuitTicket && autoQuitEnabled && !wantsToQuit &&
        phase == .blocked && pendingApplicationIDs.contains(id) && selectedApplicationIDs.contains(id)
    }
}

public enum SessionReducer {
    public static func reduce(_ state: inout SessionState, _ event: SessionEvent) -> [SessionEffect] {
        var effects: [SessionEffect] = []
        switch event {
        case .startGuard:
            guard state.phase == .idle, !state.wantsToQuit else { return [] }
            state.guardOperation += 1
            state.activationInFlight = state.guardOperation
            state.needsRestoration = true
            state.phase = .arming
            state.vpn = .unverified
            state.lastConfirmedConnected = false
            state.autoQuitArmed = false
            state.errorMessage = nil
            effects.append(.activateGuard(operation: state.guardOperation))

        case let .guardActivationCompleted(operation, result):
            guard state.activationInFlight == operation else { return [] }
            state.activationInFlight = nil
            // Cancellation cannot undo an already issued backend mutation.
            // Drain it and require another restore ACK before allowing exit.
            guard state.phase == .arming, state.guardOperation == operation, !state.wantsToQuit else {
                requestRestoration(&state, effects: &effects)
                return effects
            }
            switch result {
            case let .verified(signal):
                state.vpn = signal
                state.phase = signal == .connected ? .protected : .blocked
                state.lastConfirmedConnected = signal == .connected
                state.autoQuitArmed = signal == .connected && state.autoQuitEnabled
            case let .failed(message):
                state.phase = .fault
                state.errorMessage = message
            }

        case let .vpnChanged(signal):
            guard state.phase == .protected || state.phase == .blocked else { return [] }
            state.vpn = signal
            switch signal {
            case .connected:
                cancelApplicationQuits(&state, effects: &effects)
                state.phase = .protected
                state.lastConfirmedConnected = true
                state.autoQuitArmed = state.autoQuitEnabled
            case .disconnected:
                state.phase = .blocked
                if state.lastConfirmedConnected && state.autoQuitArmed && state.autoQuitEnabled {
                    state.autoQuitTicket += 1
                    state.pendingApplicationIDs = state.selectedApplicationIDs
                    if !state.pendingApplicationIDs.isEmpty {
                        effects.append(.quitApplications(ids: state.pendingApplicationIDs.sorted(), ticket: state.autoQuitTicket))
                    }
                }
                state.lastConfirmedConnected = false
                state.autoQuitArmed = false
            case .unverified:
                state.phase = .blocked
            }

        case let .backendFailed(message):
            guard state.phase == .protected || state.phase == .blocked || state.phase == .arming else { return [] }
            cancelApplicationQuits(&state, effects: &effects)
            state.autoQuitArmed = false
            state.phase = .fault
            state.errorMessage = message

        case let .existingGuardNeedsRestoration(message):
            guard state.phase == .idle, !state.wantsToQuit else { return [] }
            state.needsRestoration = true
            state.phase = .fault
            state.errorMessage = message

        case let .setAutoQuit(enabled):
            guard !state.wantsToQuit else { return [] }
            state.autoQuitEnabled = enabled
            if enabled {
                state.autoQuitArmed = state.phase == .protected && state.vpn == .connected
            } else {
                state.autoQuitArmed = false
                cancelApplicationQuits(&state, effects: &effects)
            }

        case let .setSelectedApplications(ids):
            guard !state.wantsToQuit else { return [] }
            let removed = state.pendingApplicationIDs.subtracting(ids)
            state.selectedApplicationIDs = ids
            state.pendingApplicationIDs.subtract(removed)
            if !removed.isEmpty { effects.append(.cancelApplicationQuits(ids: removed.sorted())) }

        case let .applicationDidQuit(id, ticket):
            guard ticket == state.autoQuitTicket else { return [] }
            state.pendingApplicationIDs.remove(id)

        case .stopGuard:
            cancelApplicationQuits(&state, effects: &effects)
            state.autoQuitArmed = false
            if state.phase != .idle && state.phase != .restoring {
                requestRestoration(&state, effects: &effects)
            }

        case .normalQuit:
            state.wantsToQuit = true
            state.autoQuitEnabled = false
            cancelApplicationQuits(&state, effects: &effects)
            state.autoQuitArmed = false
            changeKeepAwake(&state, to: .off, effects: &effects)
            if state.phase != .restoring { requestRestoration(&state, effects: &effects) }

        case .retryRestoration:
            guard state.phase == .fault, state.needsRestoration else { return [] }
            requestRestoration(&state, effects: &effects)

        case let .restorationCompleted(operation, success, message):
            guard operation == state.guardOperation, state.phase == .restoring else { return [] }
            guard success else {
                state.phase = .fault
                state.errorMessage = message ?? "Restoration is incomplete. Retry before quitting."
                return []
            }
            // A successful early stop is insufficient while activation is still in flight.
            guard state.activationInFlight == nil else { return [] }
            state.needsRestoration = false
            state.phase = .idle
            state.vpn = .unverified
            state.lastConfirmedConnected = false
            state.errorMessage = nil
            if state.wantsToQuit { effects.append(.exitApplication) }

        case let .setKeepAwake(choice):
            guard !state.wantsToQuit else { return [] }
            if case let .forDuration(seconds) = choice, !seconds.isFinite || seconds <= 0 {
                changeKeepAwake(&state, to: .off, effects: &effects)
                state.errorMessage = "Choose a positive keep-awake duration."
            } else if choice != state.keepAwake {
                changeKeepAwake(&state, to: choice, effects: &effects)
            }

        case let .wakeAcquisitionCompleted(ticket, success):
            if ticket == state.wakeTicket && !state.wakeAcquiring { return [] }
            guard ticket == state.wakeTicket, state.wakeAcquiring, state.keepAwake != .off, !state.wantsToQuit else {
                // Release only the stale acquisition, never a newer lease.
                return success ? [.releaseWake(ticket: ticket)] : []
            }
            state.wakeAcquiring = false
            state.wakeActive = success
            if success {
                if case let .forDuration(seconds) = state.keepAwake {
                    effects.append(.scheduleWakeTimeout(ticket: ticket, seconds: seconds))
                }
            } else {
                state.keepAwake = .off
                state.errorMessage = "Keeping this Mac awake could not be enabled."
                effects.append(.cancelWakeTimeout)
                effects.append(.releaseWake(ticket: ticket))
            }

        case let .wakeDurationElapsed(ticket):
            guard ticket == state.wakeTicket, state.wakeActive,
                  case .forDuration = state.keepAwake else { return [] }
            changeKeepAwake(&state, to: .off, effects: &effects)
        }
        return effects
    }

    private static func cancelApplicationQuits(_ state: inout SessionState, effects: inout [SessionEffect]) {
        state.autoQuitTicket += 1
        if !state.pendingApplicationIDs.isEmpty {
            effects.append(.cancelApplicationQuits(ids: state.pendingApplicationIDs.sorted()))
            state.pendingApplicationIDs.removeAll()
        }
    }

    private static func requestRestoration(_ state: inout SessionState, effects: inout [SessionEffect]) {
        state.guardOperation += 1
        state.needsRestoration = true
        state.phase = .restoring
        state.errorMessage = nil
        effects.append(.restoreGuard(operation: state.guardOperation))
    }

    private static func changeKeepAwake(_ state: inout SessionState, to choice: KeepAwakeChoice, effects: inout [SessionEffect]) {
        effects.append(.cancelWakeTimeout)
        if state.wakeActive || state.wakeAcquiring { effects.append(.releaseWake(ticket: state.wakeTicket)) }
        state.wakeTicket += 1
        state.keepAwake = choice
        state.wakeActive = false
        state.wakeAcquiring = choice != .off
        if state.wakeAcquiring { effects.append(.acquireWake(ticket: state.wakeTicket)) }
    }
}
