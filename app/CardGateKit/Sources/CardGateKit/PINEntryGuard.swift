/// Guards the PIN dialog against input meant for another app: every PIN the card rejects counts
/// towards locking it. Typing that arrives faster than a person can react to the new dialog is
/// discarded, and so is typing that follows it without a pause – keeping the end of such a burst
/// could leave a wrong PIN of a valid length. Enter is ignored a little longer. Typing that starts
/// later is never dropped.
public struct PINEntryGuard: Sendable {
    /// Nobody reacts to a newly shown dialog this fast: such typing was meant for another app. Also
    /// the pause that ends a discarded burst.
    public static let discardTypingFor: Duration = .milliseconds(300)
    /// An Enter this soon was most likely meant for another app.
    public static let blockSubmitFor: Duration = .milliseconds(700)

    private let shownAt: ContinuousClock.Instant
    private var lastDiscarded: ContinuousClock.Instant?

    public init(shownAt: ContinuousClock.Instant = .now) {
        self.shownAt = shownAt
    }

    /// Whether a keystroke typed now is kept; a discarded one extends the discarded burst.
    public mutating func acceptsTyping(at now: ContinuousClock.Instant = .now) -> Bool {
        let tooSoon = now - shownAt < Self.discardTypingFor
        let continuesBurst = lastDiscarded.map { now - $0 < Self.discardTypingFor } ?? false
        guard tooSoon || continuesBurst else { return true }
        lastDiscarded = now
        return false
    }

    public func acceptsSubmit(at now: ContinuousClock.Instant = .now) -> Bool {
        now - shownAt >= Self.blockSubmitFor
    }
}
