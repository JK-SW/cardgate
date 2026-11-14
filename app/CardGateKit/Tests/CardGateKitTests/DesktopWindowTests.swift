import CardGateKit
import CoreGraphics
import Testing

struct DesktopWindowTests {
    /// An entry as `CGWindowListCopyWindowInfo` returns it.
    static func info(
        pid: Int32, number: CGWindowID, frame: CGRect, layer: Int = 0, onScreen: Bool = true
    ) -> [String: Any] {
        [
            kCGWindowOwnerPID as String: pid, kCGWindowNumber as String: number, kCGWindowLayer as String: layer,
            kCGWindowBounds as String: frame.dictionaryRepresentation, kCGWindowIsOnscreen as String: onScreen,
        ]
    }

    static var windows: [[String: Any]] {
        [
            info(pid: 7, number: 1, frame: CGRect(x: 0, y: 0, width: 2000, height: 1200)),  // another app
            info(pid: 42, number: 2, frame: CGRect(x: 0, y: 0, width: 3000, height: 30), layer: 25),  // a menu
            info(pid: 42, number: 3, frame: CGRect(x: 10, y: 40, width: 400, height: 300)),  // a dialog
            info(pid: 42, number: 4, frame: CGRect(x: 100, y: 60, width: 1280, height: 800)),
        ]
    }

    @Test func findsTheClientsLargestNormalWindow() {
        let window = DesktopWindow.find(of: 42, in: Self.windows)
        let frame = CGRect(x: 100, y: 60, width: 1280, height: 800)
        #expect(window == DesktopWindow(number: 4, frame: frame, isOnScreen: true))
        #expect(DesktopWindow.find(of: 99, in: Self.windows) == nil)
    }

    @Test func prefersAWindowOnScreen() {
        let windows = [
            Self.info(pid: 42, number: 5, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), onScreen: false),
            Self.info(pid: 42, number: 6, frame: CGRect(x: 0, y: 0, width: 800, height: 600)),
        ]
        #expect(DesktopWindow.find(of: 42, in: windows)?.number == 6)
        // Minimized: found, but not on screen.
        #expect(DesktopWindow.find(of: 42, in: [windows[0]])?.isOnScreen == false)
    }

    @Test func looksUpTheKnownWindow() {
        let dialog = DesktopWindow.window(3, of: 42, in: Self.windows)
        #expect(dialog?.frame == CGRect(x: 10, y: 40, width: 400, height: 300))
        #expect(DesktopWindow.window(1, of: 42, in: Self.windows) == nil)  // not the client's
        #expect(DesktopWindow.window(8, of: 42, in: []) == nil)  // closed
    }

    @Test func noticeIsOnScreenOnlyOverTheDesktopInFront() {
        let visible = DesktopWindow(number: 1, frame: .zero, isOnScreen: true)
        let minimized = DesktopWindow(number: 1, frame: .zero, isOnScreen: false)
        #expect(SessionWindowPolicy.reconnectNoticeVisible(window: visible, clientActive: true))
        #expect(!SessionWindowPolicy.reconnectNoticeVisible(window: visible, clientActive: false))  // another app
        #expect(!SessionWindowPolicy.reconnectNoticeVisible(window: minimized, clientActive: true))
        #expect(!SessionWindowPolicy.reconnectNoticeVisible(window: nil, clientActive: true))
    }

    @Test func desktopAppearsOnceNotAfterReconnecting() {
        #expect(SessionPhase.connected.desktopAppears(after: .connectingComputer))
        #expect(SessionPhase.connected.desktopAppears(after: nil))
        #expect(!SessionPhase.connected.desktopAppears(after: .reconnecting))
        #expect(!SessionPhase.reconnecting.desktopAppears(after: .connected))
    }
}
