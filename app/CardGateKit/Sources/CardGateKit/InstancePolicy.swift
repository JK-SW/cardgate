public import Foundation

/// A running process with CardGate's or the client's bundle identifier.
public struct RunningInstance: Equatable, Sendable {
    public var pid: Int32
    /// A regular app with a Dock icon; the PIN dialog (`CardGate --askpass`) and the card check
    /// run the same executable without one.
    public var isRegularApp: Bool
    public var bundleURL: URL?

    public init(pid: Int32, isRegularApp: Bool, bundleURL: URL?) {
        self.pid = pid
        self.isRegularApp = isRegularApp
        self.bundleURL = bundleURL
    }
}

/// One CardGate per user session; clients it started never outlive it.
public enum InstancePolicy {
    /// Another running CardGate among the processes with CardGate's bundle identifier.
    public static func otherInstance(among running: [RunningInstance], current pid: Int32) -> RunningInstance? {
        running.first { $0.pid != pid && $0.isRegularApp }
    }

    /// Clients of this app (`app`: its bundle) still running when it starts: CardGate crashed or
    /// was force quit while connected. Clients elsewhere (another copy, a developer build of the
    /// helper) are left alone.
    public static func orphanedClients(among clients: [RunningInstance], app: URL) -> [RunningInstance] {
        let own = FreeRDPCommand.clientApp(in: app).standardizedFileURL.path(percentEncoded: false)
        return clients.filter { client in
            client.bundleURL.map { $0.standardizedFileURL.path(percentEncoded: false) } == own
        }
    }
}
