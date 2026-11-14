public import CoreGraphics

/// The remote desktop window as the window server lists it (`CGWindowListCopyWindowInfo`). Its
/// number, bounds and on-screen state need no screen recording permission.
public struct DesktopWindow: Equatable, Sendable {
    public var number: CGWindowID
    /// Window server coordinates: origin at the top left of the main display, y downwards.
    public var frame: CGRect
    /// False when minimized or on another Space.
    public var isOnScreen: Bool

    public init(number: CGWindowID, frame: CGRect, isOnScreen: Bool) {
        self.number = number
        self.frame = frame
        self.isOnScreen = isOnScreen
    }

    /// One entry of a window list, if it is a normal window (layer 0) of the process `pid`.
    init?(_ info: [String: Any], pid: Int32) {
        guard (info[kCGWindowOwnerPID as String] as? Int32) == pid,
            (info[kCGWindowLayer as String] as? Int) == 0,
            let number = info[kCGWindowNumber as String] as? CGWindowID,
            let bounds = info[kCGWindowBounds as String] as? [String: Any],
            let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary)
        else { return nil }
        self.init(number: number, frame: frame, isOnScreen: info[kCGWindowIsOnscreen as String] as? Bool ?? false)
    }

    /// The client's desktop window in a list of all windows: its largest normal window, preferring
    /// one on screen.
    public static func find(of pid: Int32, in windows: [[String: Any]]) -> DesktopWindow? {
        windows.compactMap { DesktopWindow($0, pid: pid) }.max { lhs, rhs in
            (lhs.isOnScreen ? 1 : 0, lhs.frame.width * lhs.frame.height)
                < (rhs.isOnScreen ? 1 : 0, rhs.frame.width * rhs.frame.height)
        }
    }

    /// The window `number` of the process `pid` in a list (e.g. the list of just that window).
    public static func window(_ number: CGWindowID, of pid: Int32, in windows: [[String: Any]]) -> DesktopWindow? {
        windows.lazy.compactMap { DesktopWindow($0, pid: pid) }.first { $0.number == number }
    }
}
