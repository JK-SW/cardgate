import Foundation
import Synchronization

/// Lets exactly one of several racing callbacks finish.
final class Once: Sendable {
    private let claimed = Mutex(false)

    func claim() -> Bool {
        claimed.withLock { claimed in
            defer { claimed = true }
            return !claimed
        }
    }
}

extension Duration {
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// The result of `work` (run on a global queue), or `fallback` when it takes longer than `timeout`;
/// the work then goes on, its result unused (blocking system calls cannot be cancelled).
func withTimeout<T: Sendable>(_ timeout: Duration, fallback: T, _ work: @escaping @Sendable () -> T) async -> T {
    let once = Once()
    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let result = work()
            if once.claim() { continuation.resume(returning: result) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout.timeInterval) {
            if once.claim() { continuation.resume(returning: fallback) }
        }
    }
}
