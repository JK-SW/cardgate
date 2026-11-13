public import Foundation

/// What happens to the PIN dialog (its own process, see `AskPassCommand`); posted as distributed
/// notifications without any data so the app can show the right status.
public enum PINDialogEvent: String, CaseIterable, Sendable {
    case shown, submitted, cancelled, timedOut

    public var notification: Notification.Name {
        Notification.Name("io.github.jk-sw.cardgate.pin-prompt.\(rawValue)")
    }
}

/// Addresses the messages between the app and the PIN dialog. Each connection gets a random
/// session ID in the client's environment; the dialog inherits it from the client and names it in
/// every message, so the app ignores dialogs of other clients (another CardGate copy, another
/// process) and closes only the dialog of its own connection.
public enum PINDialogMessages {
    /// Posted by the app on Cancel or Disconnect: the dialog of that session closes at once.
    public static let close = Notification.Name("io.github.jk-sw.cardgate.pin-prompt.close")

    /// The environment variable with the session ID.
    public static let sessionVariable = "CARDGATE_PIN_SESSION"

    public static func newSessionID() -> String {
        UUID().uuidString
    }

    /// The session ID of the environment, if it holds a usable one.
    public static func sessionID(in environment: [String: String]) -> String? {
        environment[sessionVariable].flatMap { UUID(uuidString: $0)?.uuidString }
    }

    /// The notification came from the dialog of `session`.
    public static func isFrom(session: String?, sender: Any?) -> Bool {
        guard let session else { return false }
        return (sender as? String) == session
    }
}
