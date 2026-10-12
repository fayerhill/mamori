import XCTest
import MamoriSystem
@testable import Mamori

@MainActor
final class AppModelTests: XCTestCase {
    func testPreviewUninstallCannotDeleteOrEndTheSession() async {
        let model = AppModel(demo: true)
        let bundle = Bundle.main.bundleURL
        let existed = FileManager.default.fileExists(atPath: bundle.path)
        model.completeUninstall()
        XCTAssertTrue(model.showError)
        XCTAssertEqual(model.errorMessage, model.t(.uninstallPreview))
        XCTAssertFalse(model.uninstallInProgress)
        XCTAssertFalse(model.session.wantsToQuit)
        XCTAssertEqual(FileManager.default.fileExists(atPath: bundle.path), existed)
        await stop(model)
    }

    func testManualDisconnectRemainsBlockedUntilExplicitStop() async {
        let model = AppModel(demo: true)
        model.toggleGuard()
        await settle()
        XCTAssertEqual(model.session.phase, .protected)
        model.simulateVPN(false)
        XCTAssertEqual(model.session.phase, .blocked)
        XCTAssertTrue(model.guardIsActive)
        XCTAssertTrue(model.awakeEnabled)
        model.simulateVPN(false)
        XCTAssertEqual(model.session.phase, .blocked)
        model.toggleGuard()
        await settle()
        XCTAssertEqual(model.session.phase, .idle)
        XCTAssertTrue(model.awakeEnabled)
        await stop(model)
    }

    func testQuitDisablesAllSessionActionsBeforeExit() async {
        let model = AppModel(demo: true)
        model.setAutoQuit(true)
        model.toggleGuard()
        await settle()
        var exited = false
        model.onExit = { exited = true }
        model.beginQuit()
        XCTAssertFalse(model.autoQuitEnabled)
        XCTAssertFalse(model.awakeEnabled)
        XCTAssertTrue(model.session.wantsToQuit)
        XCTAssertFalse(model.canConfigure)
        XCTAssertFalse(exited)
        await settle()
        XCTAssertEqual(model.session.phase, .idle)
        XCTAssertTrue(exited)
    }

    func testRawConnectedEvidenceCannotOverrideBlockedGuard() async {
        let model = AppModel(demo: true)
        model.toggleGuard()
        await settle()
        model.simulateVPN(false)
        XCTAssertEqual(model.session.phase, .blocked)
        model.recordConnectionEvidence(VPNSnapshot(state: .connected, label: "Stale local evidence", interface: "utun9", evidence: []))
        XCTAssertTrue(model.vpnConnected)
        XCTAssertEqual(model.session.phase, .blocked)
        XCTAssertTrue(model.needsAttention)
        await stop(model)
    }

    func testAllInterfaceCopyHasThreeNonemptyTranslations() {
        for copy in Copy.allCases {
            for language in AppLanguage.allCases {
                XCTAssertFalse(copy.text(language).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        XCTAssertNotEqual(Copy.completeUninstall.text(.english), Copy.completeUninstall.text(.chinese))
        XCTAssertNotEqual(Copy.completeUninstall.text(.english), Copy.completeUninstall.text(.japanese))
    }

    func testUnconfirmedObserverDoesNotVetoConfigurationForHelperVerification() async {
        let model = AppModel(demo: true)
        model.recordConnectionEvidence(VPNSnapshot(state: .unconfirmed, label: "Client not visible", evidence: []))
        model.tunnelInterface = " utun9 "
        model.gatewayAddresses = "203.0.113.10, 203.0.113.11"
        XCTAssertFalse(model.vpnConnected)
        XCTAssertTrue(model.validateGuardInput())
        XCTAssertFalse(model.showError)
        // Accepting input never claims enforcement; the helper must still verify it.
        XCTAssertEqual(model.session.phase, .idle)
        await stop(model)
    }

    func testMissingTunnelDoesNotAskForAnAlreadyEnteredGateway() async {
        let model = AppModel(demo: true)
        model.tunnelInterface = ""
        model.gatewayAddresses = "203.0.113.10"
        XCTAssertFalse(model.validateGuardInput())
        XCTAssertEqual(model.errorMessage, model.t(.tunnelHelp))
        XCTAssertEqual(model.screen, .connection)
        await stop(model)
    }

    func testMissingAndInvalidGatewaysHaveDistinctGuidance() async {
        let model = AppModel(demo: true)
        model.tunnelInterface = "utun9"
        model.gatewayAddresses = ""
        XCTAssertFalse(model.validateGuardInput())
        XCTAssertEqual(model.errorMessage, model.t(.gatewayRequired))
        model.gatewayAddresses = "vpn.example.com"
        XCTAssertFalse(model.validateGuardInput())
        XCTAssertEqual(model.errorMessage, model.t(.gatewayInvalid))
        await stop(model)
    }

    private func settle() async { try? await Task.sleep(for: .milliseconds(400)) }

    private func stop(_ model: AppModel) async {
        model.beginQuit()
        await settle()
    }
}
