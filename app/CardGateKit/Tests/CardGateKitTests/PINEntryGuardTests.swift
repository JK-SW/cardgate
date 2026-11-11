import CardGateKit
import Testing

struct PINEntryGuardTests {
    let shown = ContinuousClock.now

    /// Which keystrokes typed this many milliseconds after the dialog appeared are kept.
    private func kept(_ milliseconds: [Int]) -> [Bool] {
        var entry = PINEntryGuard(shownAt: shown)
        return milliseconds.map { entry.acceptsTyping(at: shown + .milliseconds($0)) }
    }

    @Test func discardsTypingFasterThanAnyReaction() {
        #expect(kept([200]) == [false])
        #expect(kept([300]) == [true])
    }

    /// A PIN typed quickly is kept; only an Enter right after the dialog appeared is ignored.
    @Test func keepsQuickTypingButNotAnEarlyEnter() {
        #expect(kept([400, 450, 500]) == [true, true, true])
        let entry = PINEntryGuard(shownAt: shown)
        #expect(!entry.acceptsSubmit(at: shown + .milliseconds(600)))
        #expect(entry.acceptsSubmit(at: shown + .milliseconds(700)))
    }

    /// Typing that started too soon is discarded as long as it goes on: its end alone could be
    /// a wrong PIN of a valid length. After a pause typing is kept again.
    @Test func discardsTheRestOfABurstThatStartedTooSoon() {
        #expect(kept([250, 350, 500, 800, 850]) == [false, false, false, true, true])
    }
}
