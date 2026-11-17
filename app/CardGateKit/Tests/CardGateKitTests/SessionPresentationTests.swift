import CardGateKit
import Testing

struct SessionPresentationTests {
    @Test func stepsFollowTheAttempt() {
        #expect(SessionPhase.starting.connectionStep == 0)
        #expect(SessionPhase.waitingForPIN.connectionStep == 1)
        #expect(SessionPhase.authenticatingGateway.connectionStep == 2)
        #expect(SessionPhase.connectingComputer.connectionStep == 3)
        #expect(SessionPhase.connected.connectionStep == nil)
        #expect(SessionPhase.reconnecting.connectionStep == nil)
        #expect(SessionPhase.ended(.closedByUser).connectionStep == nil)
    }

    @Test func safetyStopsAndALockedCardAreErrors() {
        for failure: SessionFailure in [
            .cardLocked, .untrustedCertificate, .gatewayCertificateNotPublic, .gatewayCertificateChanged,
        ] {
            #expect(failure.tone == .error)
        }
        for failure: SessionFailure in [.wrongPIN, .gatewayUnreachable, .connectionLost, .other("0x1")] {
            #expect(failure.tone == .warning)
        }
    }
}
