public import Foundation

/// App settings that apply to every connection (CardGate → Settings). In Settings all are on until
/// the user turns them off (`init(defaults:question:)`).
public struct SessionOptions: Equatable, Sendable {
    /// Keep-alive packets to the gateway and automatic reconnection after an outage.
    public var keepConnection: Bool
    /// The Mac does not go to sleep when idle while connected (the display may still turn off; closing
    /// the lid or choosing Sleep still puts it to sleep).
    public var preventSleep: Bool
    /// Closing the remote desktop window asks first. `nil`: closes without asking.
    public var disconnectQuestion: DisconnectQuestion?

    public init(keepConnection: Bool, preventSleep: Bool, disconnectQuestion: DisconnectQuestion?) {
        self.keepConnection = keepConnection
        self.preventSleep = preventSleep
        self.disconnectQuestion = disconnectQuestion
    }

    /// Keys in the app's user defaults.
    public enum Key {
        public static let keepConnection = "KeepConnection"
        public static let preventSleep = "PreventSleepWhileConnected"
        public static let confirmDisconnect = "ConfirmDisconnect"
    }

    /// Every option is on until the user turns it off (also the default of the Settings switches).
    public static let onByDefault = true

    /// Nothing of it: the client as it is (e.g. for a command built without the app settings).
    public static let off = SessionOptions(keepConnection: false, preventSleep: false, disconnectQuestion: nil)

    /// The options saved in `defaults`; an option never changed is on.
    /// - Parameter question: the question to ask before disconnecting, in the user's language.
    public init(defaults: UserDefaults, question: DisconnectQuestion) {
        func isOn(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? Self.onByDefault }
        self.init(
            keepConnection: isOn(Key.keepConnection), preventSleep: isOn(Key.preventSleep),
            disconnectQuestion: isOn(Key.confirmDisconnect) ? question : nil)
    }

    /// Seconds without anything sent after which a keep-alive packet goes to the gateway. Some
    /// gateways or proxies close a tunnel that is idle for a few minutes.
    public static let keepAliveSeconds = 60
    /// Reconnection attempts after an outage; the client waits 15 s between them (its connect
    /// timeout) plus up to 15 s for each attempt, so it gives up after 2.5 to 5 minutes.
    public static let reconnectAttempts = 10
}

/// The question the client asks when its window is closed (patched FreeRDP, 0011).
public struct DisconnectQuestion: Equatable, Sendable {
    public var title: String
    public var detail: String
    public var disconnect: String
    public var cancel: String

    public init(title: String, detail: String, disconnect: String, cancel: String) {
        self.title = title
        self.detail = detail
        self.disconnect = disconnect
        self.cancel = cancel
    }

    /// Environment variables the client reads.
    var environment: [String: String] {
        [
            "FREERDP_CONFIRM_DISCONNECT": title,
            "FREERDP_CONFIRM_DISCONNECT_DETAIL": detail,
            "FREERDP_CONFIRM_DISCONNECT_BUTTON": disconnect,
            "FREERDP_CONFIRM_DISCONNECT_CANCEL": cancel,
        ]
    }
}
