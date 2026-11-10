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

    public func reopen(isActive: Bool) -> Reopen {
        guard isShowingDesktop else { return .standard }
        return isActive ? .showDesktop : .nothing
    }
}
