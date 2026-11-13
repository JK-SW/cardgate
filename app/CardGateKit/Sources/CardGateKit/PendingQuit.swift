/// Quitting CardGate while a connection runs: the app asks, ends the client and quits only once
/// the client has ended (or a deadline passed), so no client outlives the app.
public struct PendingQuit: Sendable {
    public enum Decision: Equatable, Sendable {
        /// Nothing runs.
        case quitNow
        /// Ask the user, then `begin()` and wait.
        case ask
        /// A quit already waits for the client (another Quit, logout): it will finish.
        case keepWaiting
    }

    public private(set) var isWaiting = false

    public init() {}

    public func decide(sessionRunning: Bool) -> Decision {
        if isWaiting { return .keepWaiting }
        return sessionRunning ? .ask : .quitNow
    }

    public mutating func begin() {
        isWaiting = true
    }

    /// The client ended or the deadline passed. Returns `true` exactly once per quit: then the
    /// app replies to the system that it may quit.
    public mutating func finish() -> Bool {
        defer { isWaiting = false }
        return isWaiting
    }
}
