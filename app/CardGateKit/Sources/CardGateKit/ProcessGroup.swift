public import Foundation

/// Stopping a helper process that may hang inside a third-party library (the card check).
public enum ProcessGroup {
    /// Kills the process and everything in its process group (processes a card driver started). A
    /// process that did not get to start its own group yet (it hung earlier) is killed by itself.
    /// - Parameter leader: the process, which made itself the leader of its group (`setpgid(0, 0)`).
    public static func kill(leader: pid_t) {
        if killpg(leader, SIGKILL) != 0 {
            _ = Darwin.kill(leader, SIGKILL)
        }
    }
}
