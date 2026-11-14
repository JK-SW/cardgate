public import CoreGraphics

/// Which window CardGate shows while a connection runs: one at a time – CardGate's window until
/// the remote desktop appears, then the remote desktop (the client has no Dock icon, so CardGate
/// stands for it), and CardGate's window again when the session ends.
public struct SessionWindowPolicy: Equatable, Sendable {
    public private(set) var isShowingDesktop = false

    /// What a click on CardGate's Dock icon does.
    public enum Reopen: Equatable, Sendable {
        /// No remote desktop: the system's default (show CardGate's window).
        case standard
        /// Bring the remote desktop forward.
        case showDesktop
        /// CardGate is not active yet; it hands over once active (`forwardsActivation`).
        case nothing
    }

    public init() {}

    /// The remote desktop appeared: CardGate's window hides and the desktop gets the focus.
    public mutating func desktopShown() {
        isShowingDesktop = true
    }

    /// Returns whether CardGate's window must come back (it was hidden for the desktop).
    public mutating func sessionEnded() -> Bool {
        defer { isShowingDesktop = false }
        return isShowingDesktop
    }

    /// Whether CardGate, just activated (Dock, app switcher), hands the focus to the remote
    /// desktop. Not while one of its windows or a modal alert (e.g. quit and disconnect?) is open.
    public func forwardsActivation(windowVisible: Bool, modalOpen: Bool) -> Bool {
        isShowingDesktop && !windowVisible && !modalOpen
    }

    /// Whether a notice shows over the remote desktop: the connection broke and the client
    /// reconnects; meanwhile the desktop keeps its last picture and does not respond.
    public func showsReconnectNotice(phase: SessionPhase?) -> Bool {
        isShowingDesktop && phase == .reconnecting
    }

    /// Whether the reconnect notice is on screen now: only over the remote desktop, i.e. while the
    /// client is the active app and its window is visible (not minimized, not on another Space).
    /// Otherwise it would float over every other app until the client gives up.
    public static func reconnectNoticeVisible(window: DesktopWindow?, clientActive: Bool) -> Bool {
        clientActive && window?.isOnScreen == true
    }

    /// Where the reconnect notice goes so that it sits in the middle of the remote desktop window
    /// (in full screen, the middle of that screen).
    /// - Parameters:
    ///   - window: the desktop window's frame as the window server reports it (origin at the top
    ///     left of the main display, y downwards).
    ///   - mainDisplayHeight: the height of the main display (the one with the menu bar origin).
    ///   - size: the notice's size.
    /// - Returns: the notice's origin in AppKit coordinates (origin at the bottom left, y upwards).
    public static func reconnectNoticeOrigin(window: CGRect, mainDisplayHeight: CGFloat, size: CGSize) -> CGPoint {
        CGPoint(
            x: (window.midX - size.width / 2).rounded(),
            y: (mainDisplayHeight - window.midY - size.height / 2).rounded())
    }

    public func reopen(isActive: Bool) -> Reopen {
        guard isShowingDesktop else { return .standard }
        return isActive ? .showDesktop : .nothing
    }
}

/// How often the reconnect notice looks where the remote desktop window is. macOS reports moves of
/// another app's window only through the Accessibility API (a permission the user would have to
/// give), so the notice checks: rarely while the window stays put, often while it moves.
public struct NoticeFollowPace: Equatable, Sendable {
    /// Seconds between checks while the window stays put.
    public static let idle: Double = 0.5
    /// Seconds between checks while the window moves (smooth enough to follow a drag).
    public static let moving: Double = 1.0 / 30
    /// Seconds without a move after which the checks slow down again.
    public static let settle: Double = 1

    public private(set) var interval = idle
    private var lastMove: Double?

    public init() {}

    /// Records one check and returns whether the interval changed.
    /// - Parameters:
    ///   - moved: the window was somewhere else than at the check before.
    ///   - now: the time of the check in seconds (any steady clock).
    public mutating func checked(moved: Bool, now: Double) -> Bool {
        if moved { lastMove = now }
        let next = lastMove.map { now - $0 < Self.settle } == true ? Self.moving : Self.idle
        defer { interval = next }
        return next != interval
    }
}
