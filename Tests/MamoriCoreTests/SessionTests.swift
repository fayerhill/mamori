import XCTest
@testable import MamoriCore

final class SessionTests: XCTestCase {
    private func send(_ event: SessionEvent, to state: inout SessionState) -> [SessionEffect] {
        SessionReducer.reduce(&state, event)
    }

    private func activate(_ state: inout SessionState, signal: VPNConnectionSignal = .connected) {
        _ = send(.startGuard, to: &state)
        _ = send(.guardActivationCompleted(operation: state.guardOperation, result: .verified(signal)), to: &state)
    }

    private func configureAutoQuit(_ state: inout SessionState) {
        _ = send(.setSelectedApplications(["app.alpha", "app.beta"]), to: &state)
        _ = send(.setAutoQuit(true), to: &state)
    }

    func testActivationNeedsVerificationAndIgnoresForeignCompletion() {
        var state = SessionState()
        XCTAssertEqual(send(.startGuard, to: &state), [.activateGuard(operation: 1)])
        XCTAssertEqual(state.phase, .arming)
        XCTAssertEqual(send(.guardActivationCompleted(operation: 42, result: .verified(.connected)), to: &state), [])
        XCTAssertEqual(state.phase, .arming)
        XCTAssertEqual(send(.guardActivationCompleted(operation: 1, result: .verified(.connected)), to: &state), [])
        XCTAssertEqual(state.phase, .protected)
        XCTAssertEqual(send(.guardActivationCompleted(operation: 1, result: .failed("Duplicate")), to: &state), [])
        XCTAssertEqual(state.phase, .protected)
    }

    func testUnverifiedEvidenceNeverClaimsConnectedOrQuitsApps() {
        var state = SessionState()
        configureAutoQuit(&state)
        activate(&state, signal: .unverified)
        XCTAssertEqual(state.phase, .blocked)
        XCTAssertEqual(send(.vpnChanged(.disconnected), to: &state), [])
        XCTAssertTrue(state.pendingApplicationIDs.isEmpty)
        _ = send(.vpnChanged(.connected), to: &state)
        XCTAssertEqual(send(.vpnChanged(.unverified), to: &state), [])
        XCTAssertEqual(state.phase, .blocked)
        XCTAssertTrue(state.pendingApplicationIDs.isEmpty)
    }

    func testConfirmedLossQuitsSelectedAppsOnlyOnce() {
        var state = SessionState()
        configureAutoQuit(&state)
        activate(&state)
        let effects = send(.vpnChanged(.disconnected), to: &state)
        XCTAssertEqual(effects, [.quitApplications(ids: ["app.alpha", "app.beta"], ticket: state.autoQuitTicket)])
        XCTAssertTrue(state.canPerformAutoQuit(id: "app.alpha", ticket: state.autoQuitTicket))
        XCTAssertFalse(state.canPerformAutoQuit(id: "app.other", ticket: state.autoQuitTicket))
        XCTAssertEqual(send(.vpnChanged(.disconnected), to: &state), [])
    }

    func testEnableAndAddAppsWhileDisconnectedWaitsForNextLoss() {
        var state = SessionState()
        activate(&state, signal: .disconnected)
        XCTAssertEqual(send(.setAutoQuit(true), to: &state), [])
        XCTAssertEqual(send(.setSelectedApplications(["app.alpha"]), to: &state), [])
        XCTAssertEqual(send(.vpnChanged(.disconnected), to: &state), [])
        XCTAssertTrue(state.pendingApplicationIDs.isEmpty)
        _ = send(.vpnChanged(.connected), to: &state)
        XCTAssertEqual(send(.vpnChanged(.disconnected), to: &state),
                       [.quitApplications(ids: ["app.alpha"], ticket: state.autoQuitTicket)])
        XCTAssertEqual(send(.setSelectedApplications(["app.alpha", "app.beta"]), to: &state), [])
        XCTAssertFalse(state.canPerformAutoQuit(id: "app.beta", ticket: state.autoQuitTicket))
    }

    func testDisableInvalidatesEvenAnAlreadyDispatchedTimer() {
        var state = SessionState()
        configureAutoQuit(&state)
        activate(&state)
        _ = send(.vpnChanged(.disconnected), to: &state)
        let dispatchedTicket = state.autoQuitTicket
        XCTAssertEqual(send(.setAutoQuit(false), to: &state), [.cancelApplicationQuits(ids: ["app.alpha", "app.beta"])])
        _ = send(.setAutoQuit(true), to: &state)
        XCTAssertFalse(state.canPerformAutoQuit(id: "app.alpha", ticket: dispatchedTicket))
        XCTAssertEqual(send(.applicationDidQuit(id: "app.alpha", ticket: dispatchedTicket), to: &state), [])
        XCTAssertTrue(state.pendingApplicationIDs.isEmpty)
    }

    func testDeselectCancelsOnlyRemovedAppAndReaddingDoesNotJoinOldBatch() {
        var state = SessionState()
        configureAutoQuit(&state)
        activate(&state)
        _ = send(.vpnChanged(.disconnected), to: &state)
        let ticket = state.autoQuitTicket
        XCTAssertEqual(send(.setSelectedApplications(["app.beta"]), to: &state), [.cancelApplicationQuits(ids: ["app.alpha"])])
        _ = send(.setSelectedApplications(["app.alpha", "app.beta"]), to: &state)
        XCTAssertFalse(state.canPerformAutoQuit(id: "app.alpha", ticket: ticket))
        XCTAssertTrue(state.canPerformAutoQuit(id: "app.beta", ticket: ticket))
    }

    func testReconnectOnlyCancelsOldActionsAndNeverRestartsApps() {
        var state = SessionState()
        configureAutoQuit(&state)
        activate(&state)
        _ = send(.vpnChanged(.disconnected), to: &state)
        let oldTicket = state.autoQuitTicket
        _ = send(.applicationDidQuit(id: "app.alpha", ticket: oldTicket), to: &state)
        XCTAssertEqual(send(.vpnChanged(.connected), to: &state), [.cancelApplicationQuits(ids: ["app.beta"])])
        XCTAssertEqual(state.phase, .protected)
        XCTAssertFalse(state.canPerformAutoQuit(id: "app.beta", ticket: oldTicket))
        XCTAssertTrue(state.pendingApplicationIDs.isEmpty)
    }

    func testQuitDuringActivationWaitsForLateActivationAndFinalRestore() {
        var state = SessionState()
        _ = send(.startGuard, to: &state)
        let activation = state.guardOperation
        XCTAssertTrue(send(.normalQuit, to: &state).contains(.restoreGuard(operation: 2)))
        let firstRestore = state.guardOperation
        XCTAssertEqual(send(.restorationCompleted(operation: firstRestore, success: true, message: nil), to: &state), [])
        XCTAssertEqual(state.phase, .restoring)
        XCTAssertEqual(send(.guardActivationCompleted(operation: activation, result: .verified(.connected)), to: &state),
                       [.restoreGuard(operation: 3)])
        XCTAssertEqual(send(.restorationCompleted(operation: firstRestore, success: true, message: nil), to: &state), [])
        XCTAssertEqual(state.phase, .restoring)
        XCTAssertEqual(send(.restorationCompleted(operation: 3, success: true, message: nil), to: &state), [.exitApplication])
        XCTAssertEqual(state.phase, .idle)
    }

    func testActivationFinishingBeforeFirstRestoreAckStillNeedsNewestAck() {
        var state = SessionState()
        _ = send(.startGuard, to: &state)
        _ = send(.stopGuard, to: &state)
        XCTAssertEqual(send(.guardActivationCompleted(operation: 1, result: .failed("Partially acquired")), to: &state),
                       [.restoreGuard(operation: 3)])
        XCTAssertEqual(send(.restorationCompleted(operation: 2, success: true, message: nil), to: &state), [])
        XCTAssertEqual(state.phase, .restoring)
        XCTAssertEqual(send(.startGuard, to: &state), [])
        XCTAssertEqual(send(.restorationCompleted(operation: 3, success: true, message: nil), to: &state), [])
        XCTAssertEqual(state.phase, .idle)
    }

    func testRestoreFailureKeepsRecoveryAvailableAndPreventsQuit() {
        var state = SessionState()
        activate(&state)
        _ = send(.normalQuit, to: &state)
        XCTAssertEqual(send(.restorationCompleted(operation: state.guardOperation, success: false, message: "Rules remain"), to: &state), [])
        XCTAssertEqual(state.phase, .fault)
        XCTAssertEqual(state.errorMessage, "Rules remain")
        XCTAssertTrue(state.wantsToQuit)
        XCTAssertEqual(send(.startGuard, to: &state), [])
        let effects = send(.retryRestoration, to: &state)
        XCTAssertEqual(effects, [.restoreGuard(operation: state.guardOperation)])
        XCTAssertEqual(send(.restorationCompleted(operation: state.guardOperation, success: true, message: nil), to: &state), [.exitApplication])
    }

    func testPreviousSessionCallbacksCannotChangeNewSession() {
        var state = SessionState()
        activate(&state)
        let oldActivation = state.guardOperation
        _ = send(.stopGuard, to: &state)
        let oldRestore = state.guardOperation
        _ = send(.restorationCompleted(operation: oldRestore, success: true, message: nil), to: &state)
        activate(&state)
        let current = state
        XCTAssertEqual(send(.guardActivationCompleted(operation: oldActivation, result: .verified(.disconnected)), to: &state), [])
        XCTAssertEqual(send(.restorationCompleted(operation: oldRestore, success: false, message: "Old failure"), to: &state), [])
        XCTAssertEqual(state, current)
    }

    func testStopGuardLeavesIndependentAwakeAndQuitCancelsIt() {
        var state = SessionState()
        _ = send(.setKeepAwake(.whileAppRuns), to: &state)
        let wake = state.wakeTicket
        _ = send(.wakeAcquisitionCompleted(ticket: wake, success: true), to: &state)
        activate(&state)
        XCTAssertEqual(send(.stopGuard, to: &state), [.restoreGuard(operation: state.guardOperation)])
        XCTAssertTrue(state.wakeActive)
        XCTAssertEqual(state.keepAwake, .whileAppRuns)
        let quit = send(.normalQuit, to: &state)
        XCTAssertEqual(quit, [.cancelWakeTimeout, .releaseWake(ticket: wake)])
        XCTAssertEqual(state.keepAwake, .off)
        XCTAssertFalse(state.wakeActive)
        XCTAssertEqual(send(.restorationCompleted(operation: state.guardOperation, success: true, message: nil), to: &state), [.exitApplication])
    }

    func testAppQuitCompletionDoesNotEndAwake() {
        var state = SessionState()
        configureAutoQuit(&state)
        _ = send(.setKeepAwake(.whileAppRuns), to: &state)
        _ = send(.wakeAcquisitionCompleted(ticket: state.wakeTicket, success: true), to: &state)
        activate(&state)
        _ = send(.vpnChanged(.disconnected), to: &state)
        let ticket = state.autoQuitTicket
        XCTAssertEqual(send(.applicationDidQuit(id: "app.alpha", ticket: ticket), to: &state), [])
        XCTAssertEqual(send(.applicationDidQuit(id: "app.beta", ticket: ticket), to: &state), [])
        XCTAssertTrue(state.wakeActive)
    }

    func testFailedWakeAcquireTurnsControlOff() {
        var state = SessionState()
        _ = send(.setKeepAwake(.whileAppRuns), to: &state)
        let ticket = state.wakeTicket
        XCTAssertEqual(send(.wakeAcquisitionCompleted(ticket: ticket, success: false), to: &state),
                       [.cancelWakeTimeout, .releaseWake(ticket: ticket)])
        XCTAssertEqual(state.keepAwake, .off)
        XCTAssertFalse(state.wakeActive)
        XCTAssertFalse(state.wakeAcquiring)
        XCTAssertNotNil(state.errorMessage)
    }

    func testInvalidDurationNeverAcquiresWake() {
        for duration in [0.0, -1.0, Double.infinity, Double.nan] {
            var state = SessionState()
            XCTAssertEqual(send(.setKeepAwake(.forDuration(seconds: duration)), to: &state), [.cancelWakeTimeout])
            XCTAssertEqual(state.keepAwake, .off)
            XCTAssertFalse(state.wakeAcquiring)
            XCTAssertNotNil(state.errorMessage)
        }
    }

    func testStaleWakeAcquisitionReleasesOnlyItsLease() {
        var state = SessionState()
        _ = send(.setKeepAwake(.forDuration(seconds: 60)), to: &state)
        let old = state.wakeTicket
        _ = send(.setKeepAwake(.whileAppRuns), to: &state)
        let current = state.wakeTicket
        _ = send(.wakeAcquisitionCompleted(ticket: current, success: true), to: &state)
        XCTAssertEqual(send(.wakeAcquisitionCompleted(ticket: old, success: true), to: &state), [.releaseWake(ticket: old)])
        XCTAssertEqual(send(.wakeDurationElapsed(ticket: old), to: &state), [])
        XCTAssertTrue(state.wakeActive)
        XCTAssertEqual(state.keepAwake, .whileAppRuns)
        XCTAssertEqual(send(.wakeAcquisitionCompleted(ticket: current, success: true), to: &state), [])
        XCTAssertTrue(state.wakeActive)
    }

    func testDurationBeginsAfterAcquisitionAndExpiresIndependentlyOfGuard() {
        var state = SessionState()
        XCTAssertEqual(send(.setKeepAwake(.forDuration(seconds: 120)), to: &state), [.cancelWakeTimeout, .acquireWake(ticket: 1)])
        XCTAssertEqual(send(.wakeDurationElapsed(ticket: 1), to: &state), [])
        XCTAssertEqual(send(.wakeAcquisitionCompleted(ticket: 1, success: true), to: &state), [.scheduleWakeTimeout(ticket: 1, seconds: 120)])
        XCTAssertEqual(state.phase, .idle)
        XCTAssertEqual(send(.wakeDurationElapsed(ticket: 1), to: &state), [.cancelWakeTimeout, .releaseWake(ticket: 1)])
        XCTAssertEqual(state.keepAwake, .off)
    }

    func testBackendFailureInvalidatesAutoQuitAndRequiresRestore() {
        var state = SessionState()
        configureAutoQuit(&state)
        activate(&state)
        _ = send(.vpnChanged(.disconnected), to: &state)
        let ticket = state.autoQuitTicket
        XCTAssertEqual(send(.backendFailed("Cannot verify rules"), to: &state), [.cancelApplicationQuits(ids: ["app.alpha", "app.beta"])])
        XCTAssertEqual(state.phase, .fault)
        XCTAssertFalse(state.canPerformAutoQuit(id: "app.alpha", ticket: ticket))
        XCTAssertEqual(send(.vpnChanged(.connected), to: &state), [])
        XCTAssertEqual(state.phase, .fault)
        XCTAssertEqual(send(.retryRestoration, to: &state), [.restoreGuard(operation: state.guardOperation)])
    }

    func testExistingGuardAtStartupShowsRecoveryWithoutMutatingBackend() {
        var state = SessionState()
        XCTAssertEqual(send(.existingGuardNeedsRestoration("Previous protection is still active"), to: &state), [])
        XCTAssertEqual(state.phase, .fault)
        XCTAssertEqual(state.errorMessage, "Previous protection is still active")
        XCTAssertEqual(state.guardOperation, 0)
        XCTAssertEqual(send(.startGuard, to: &state), [])
        XCTAssertEqual(send(.retryRestoration, to: &state), [.restoreGuard(operation: 1)])
        XCTAssertEqual(send(.restorationCompleted(operation: 1, success: true, message: nil), to: &state), [])
        XCTAssertEqual(state.phase, .idle)
    }

    func testNormalQuitShowsAutoQuitDisabledWhileRestorationNeedsRetry() {
        var state = SessionState()
        configureAutoQuit(&state)
        activate(&state)
        _ = send(.vpnChanged(.disconnected), to: &state)
        let oldTicket = state.autoQuitTicket
        _ = send(.normalQuit, to: &state)
        XCTAssertFalse(state.autoQuitEnabled)
        XCTAssertTrue(state.pendingApplicationIDs.isEmpty)
        XCTAssertFalse(state.canPerformAutoQuit(id: "app.alpha", ticket: oldTicket))
        _ = send(.restorationCompleted(operation: state.guardOperation, success: false, message: "Retry needed"), to: &state)
        XCTAssertEqual(state.phase, .fault)
        XCTAssertFalse(state.autoQuitEnabled)
        XCTAssertEqual(send(.setAutoQuit(true), to: &state), [])
        XCTAssertFalse(state.autoQuitEnabled)
    }
}
