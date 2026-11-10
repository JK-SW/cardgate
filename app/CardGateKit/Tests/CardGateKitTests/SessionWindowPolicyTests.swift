import CardGateKit
import Testing

struct SessionWindowPolicyTests {
    @Test func keepsCardGateUntilTheDesktopAppears() {
        let policy = SessionWindowPolicy()
        #expect(!policy.forwardsActivation(windowVisible: false, modalOpen: false))
        #expect(policy.reopen(isActive: true) == .standard)
    }

    @Test func handsActivationToTheDesktop() {
        var policy = SessionWindowPolicy()
        policy.desktopShown()
        #expect(policy.forwardsActivation(windowVisible: false, modalOpen: false))
        #expect(policy.reopen(isActive: true) == .showDesktop)
        // An inactive CardGate cannot hand over yet; it does once activated.
        #expect(policy.reopen(isActive: false) == .nothing)
    }

    @Test func keepsOpenWindowsAndAlertsInFront() {
        var policy = SessionWindowPolicy()
        policy.desktopShown()
        #expect(!policy.forwardsActivation(windowVisible: true, modalOpen: false))
        #expect(!policy.forwardsActivation(windowVisible: false, modalOpen: true))
    }

    @Test func bringsCardGateBackOnlyAfterTheDesktop() {
        var failedEarly = SessionWindowPolicy()
        let restoresAfterFailure = failedEarly.sessionEnded()
        #expect(!restoresAfterFailure)  // its window never hid

        var policy = SessionWindowPolicy()
        policy.desktopShown()
        let restores = policy.sessionEnded()
        #expect(restores)
        #expect(!policy.isShowingDesktop)
        #expect(!policy.forwardsActivation(windowVisible: false, modalOpen: false))
    }
}
