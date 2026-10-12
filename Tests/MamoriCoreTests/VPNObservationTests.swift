import MamoriCore
import Testing

struct VPNObservationTests {
    @Test func runningClientWithoutPriorTunnelIsNotAConfirmedDisconnect() {
        #expect(GlobalProtectEvidenceClassifier.classify(
            clientRunning: true, previouslyConfirmed: false, evidence: .absent
        ) == .unverified)
    }

    @Test func lostPreviouslyConfirmedTunnelIsDisconnectedEvenWithClientRunning() {
        #expect(GlobalProtectEvidenceClassifier.classify(
            clientRunning: true, previouslyConfirmed: true, evidence: .absent
        ) == .disconnected)
        #expect(GlobalProtectEvidenceClassifier.classify(
            clientRunning: true, previouslyConfirmed: true, evidence: .inactive
        ) == .disconnected)
    }

    @Test func readFailuresAndMalformedRecordsNeverConfirmLoss() {
        for evidence in [GlobalProtectTunnelEvidence.unreadable, .malformed] {
            #expect(GlobalProtectEvidenceClassifier.classify(
                clientRunning: true, previouslyConfirmed: true, evidence: evidence
            ) == .unverified)
        }
    }

    @Test func oneOwnedActiveTunnelAndTheKnownClientConfirmLocalConnection() {
        #expect(GlobalProtectEvidenceClassifier.classify(
            clientRunning: true, previouslyConfirmed: false,
            evidence: .active(interfaces: ["utun4"])
        ) == .connected)
    }

    @Test func ambiguousTunnelsOrMissingClientRemainUnverified() {
        #expect(GlobalProtectEvidenceClassifier.classify(
            clientRunning: true, previouslyConfirmed: true,
            evidence: .active(interfaces: ["utun4", "utun7"])
        ) == .unverified)
        #expect(GlobalProtectEvidenceClassifier.classify(
            clientRunning: false, previouslyConfirmed: true,
            evidence: .active(interfaces: ["utun4"])
        ) == .unverified)
    }

    @Test func staleInactiveRecordAtStartupIsNotAConfirmedTransition() {
        #expect(GlobalProtectEvidenceClassifier.classify(
            clientRunning: true, previouslyConfirmed: false, evidence: .inactive
        ) == .unverified)
    }
}
