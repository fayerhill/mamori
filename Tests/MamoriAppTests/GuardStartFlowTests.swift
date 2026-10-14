import XCTest
import MamoriCore
@testable import Mamori

@MainActor
final class GuardStartFlowTests: XCTestCase {
    func testEveryStartDiscoversAndUsesTheCurrentTunnelAndGateway() async {
        let configurations = [
            GuardConfiguration(tunnelInterface: "utun9", gatewayAddresses: ["203.0.113.10"]),
            GuardConfiguration(tunnelInterface: "utun12", gatewayAddresses: ["203.0.113.20"])
        ]
        var discoveries = 0
        var activated: [GuardConfiguration] = []
        for configuration in configurations {
            let expected = GuardStatus(phase: .protected, message: "Verified", configuration: configuration, helperAvailable: true)
            let result = await GuardStartFlow.run(discover: {
                discoveries += 1
                return GuardDiscovery(configuration: configuration, message: "Detected")
            }, activate: { current in
                activated.append(current)
                return expected
            }, isCurrent: { true })
            XCTAssertEqual(result, .activated(expected))
        }
        XCTAssertEqual(discoveries, 2)
        XCTAssertEqual(activated, configurations)
    }

    func testFailedDiscoveryExplainsFailureWithoutActivating() async {
        var activated = false
        let result = await GuardStartFlow.run(discover: {
            GuardDiscovery(message: "Connect GlobalProtect first.")
        }, activate: { _ in
            activated = true
            return GuardStatus(phase: .protected, message: "Unexpected")
        }, isCurrent: { true })
        XCTAssertEqual(result, .discoveryFailed("Connect GlobalProtect first."))
        XCTAssertFalse(activated)
    }

    func testQuitDuringDiscoveryPreventsLateActivation() async {
        var current = true
        var activated = false
        let result = await GuardStartFlow.run(discover: {
            await Task.yield()
            current = false
            return GuardDiscovery(configuration: .init(tunnelInterface: "utun9", gatewayAddresses: ["203.0.113.10"]), message: "Detected")
        }, activate: { _ in
            activated = true
            return GuardStatus(phase: .protected, message: "Unexpected")
        }, isCurrent: { current })
        XCTAssertEqual(result, .cancelled)
        XCTAssertFalse(activated)
    }

    func testAlreadyCancelledAttemptDoesNotStartDiscovery() async {
        var discovered = false
        let result = await GuardStartFlow.run(discover: {
            discovered = true
            return GuardDiscovery(message: "Unexpected")
        }, activate: { _ in
            XCTFail("Cancelled start activated protection")
            return GuardStatus(phase: .protected, message: "Unexpected")
        }, isCurrent: { false })
        XCTAssertEqual(result, .cancelled)
        XCTAssertFalse(discovered)
    }

    func testHelperActivationFailureIsNotPromotedToProtected() async {
        let failure = GuardStatus(phase: .fault, message: "PF is already enabled.", helperAvailable: true)
        let result = await GuardStartFlow.run(discover: {
            GuardDiscovery(configuration: .init(tunnelInterface: "utun9", gatewayAddresses: ["203.0.113.10"]), message: "Detected")
        }, activate: { _ in failure }, isCurrent: { true })
        XCTAssertEqual(result, .activated(failure))
    }
}
