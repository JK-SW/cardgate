import CardGateKit
import CoreGraphics
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

    @Test func noticeShowsOverTheDesktopOnlyWhileReconnecting() {
        var policy = SessionWindowPolicy()
        #expect(!policy.showsReconnectNotice(phase: .reconnecting))  // no desktop yet
        policy.desktopShown()
        #expect(policy.showsReconnectNotice(phase: .reconnecting))
        #expect(!policy.showsReconnectNotice(phase: .connected))  // restored
        #expect(!policy.showsReconnectNotice(phase: .ended(.failed(.connectionLost))))
        #expect(!policy.showsReconnectNotice(phase: .ended(.closedByUser)))
    }

    @Test func noticeSitsInTheMiddleOfTheDesktopWindow() {
        // A window in the top left corner of a 1440×900 main display.
        let origin = SessionWindowPolicy.reconnectNoticeOrigin(
            window: CGRect(x: 0, y: 25, width: 800, height: 600), mainDisplayHeight: 900,
            size: CGSize(width: 380, height: 160))
        #expect(origin == CGPoint(x: 210, y: 900 - 325 - 80))
        // Full screen on a second display right of the main one.
        let fullScreen = SessionWindowPolicy.reconnectNoticeOrigin(
            window: CGRect(x: 1440, y: 0, width: 1920, height: 1080), mainDisplayHeight: 900,
            size: CGSize(width: 380, height: 160))
        #expect(fullScreen == CGPoint(x: 1440 + 960 - 190, y: 900 - 540 - 80))
    }

    @Test func noticeChecksOftenOnlyWhileTheWindowMoves() {
        var pace = NoticeFollowPace()
        #expect(pace.interval == NoticeFollowPace.idle)
        struct Check {
            let moved: Bool
            let now: Double
            let changes: Bool
            let interval: Double
        }
        let checks = [
            Check(moved: false, now: 0, changes: false, interval: NoticeFollowPace.idle),
            Check(moved: true, now: 0.5, changes: true, interval: NoticeFollowPace.moving),  // speeds up
            Check(moved: false, now: 1.0, changes: false, interval: NoticeFollowPace.moving),  // pause in the drag
            Check(moved: true, now: 1.2, changes: false, interval: NoticeFollowPace.moving),
            Check(moved: false, now: 2.1, changes: false, interval: NoticeFollowPace.moving),
            Check(moved: false, now: 2.2, changes: true, interval: NoticeFollowPace.idle),  // still for 1 s
        ]
        for check in checks {
            let changed = pace.checked(moved: check.moved, now: check.now)
            #expect(changed == check.changes, "at \(check.now)")
            #expect(pace.interval == check.interval, "at \(check.now)")
        }
    }
}
