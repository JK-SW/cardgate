import Foundation

/// How CardGate ends the client (Cancel, Disconnect, quitting, a client left behind).
///
/// SIGTERM only queues a quit event for the client's event loop; while it connects (waiting for
/// the card, the gateway or the PIN dialog) or hangs, nothing handles it, and a second SIGTERM does
/// nothing (FreeRDP removes its handler after the first). So after a grace period the client is
/// killed: it holds the redirected card and must never outlive the request.
public enum ClientStop {
    /// How long the client may take to quit by itself. A connected client disconnects from the
    /// computer cleanly; before that there is nothing to close and Cancel should be quick.
    public static func gracePeriod(connected: Bool) -> Duration {
        connected ? .seconds(5) : .seconds(2)
    }

    /// Quitting the app waits for the client at most this long (it is killed before).
    public static func quitDeadline(connected: Bool) -> Duration {
        gracePeriod(connected: connected) + .seconds(2)
    }

    /// Asks the client to quit and kills it if it is still running after the grace period.
    /// - Parameters:
    ///   - isRunning: whether this client (not a later one) still runs.
    ///   - isolation: runs on the caller's actor (the closures may use its state).
    ///   - sleep: waits; throws when the wait is cancelled (then the client is not killed).
    public static func run(
        isolation _: isolated (any Actor)? = #isolation,
        connected: Bool,
        terminate: () -> Void,
        isRunning: () -> Bool,
        kill: () -> Void,
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) async {
        terminate()
        do {
            try await sleep(gracePeriod(connected: connected))
        } catch {
            return
        }
        if isRunning() { kill() }
    }
}
