/// The controls in the title bar of the remote desktop window (patched FreeRDP, 0023): the desktop
/// scale of the remote computer (smaller, larger, a list) and a button that shows CardGate's
/// connection log. The client shows them only with these texts, in the user's language.
public struct TitleBarControls: Equatable, Sendable {
    /// Help text of the scale control.
    public var scale: String
    public var smaller: String
    public var larger: String
    /// The list's item that returns to the scale the connection started with.
    public var connectionScale: String
    /// Help text of the log button.
    public var log: String

    public init(scale: String, smaller: String, larger: String, connectionScale: String, log: String) {
        self.scale = scale
        self.smaller = smaller
        self.larger = larger
        self.connectionScale = connectionScale
        self.log = log
    }

    /// Environment variables the client reads.
    var environment: [String: String] {
        [
            "FREERDP_TITLEBAR_SCALE": scale,
            "FREERDP_TITLEBAR_SMALLER": smaller,
            "FREERDP_TITLEBAR_LARGER": larger,
            "FREERDP_TITLEBAR_DEFAULT_SCALE": connectionScale,
            "FREERDP_TITLEBAR_LOG": log,
        ]
    }

    /// The client's line when the log button is clicked: CardGate shows its log window.
    static let showLogRequest = "the user asked to show the connection log"
    /// The client's line when the scale is changed in the title bar (a number, or each display's own).
    static let scaleChange = "desktop scale changed in the title bar"
    /// What follows `scaleChange` instead of a number: each display has its own scale again.
    static let displayScale = "the scale of each display"

    /// Only the client's own line (its function and the whole text), not the text quoted elsewhere.
    public static func asksForLog(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("[sdl_run]: " + showLogRequest)
    }

    /// Texts of the client log CardGate depends on (checked against the client binary).
    public static let logMarkers = [showLogRequest, scaleChange, displayScale]
}
