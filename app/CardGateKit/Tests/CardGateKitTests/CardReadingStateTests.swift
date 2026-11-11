import CardGateKit
import Testing

struct CardReadingStateTests {
    @Test func readsFromInsertionUntilCertificatesArrive() {
        var state = CardReadingState()
        let started = state.cardInReader(true, hasCertificates: false)
        #expect(started)
        #expect(state.isReading)
        state.certificatesChanged(found: true)
        #expect(!state.isReading)
    }

    /// At start the card is already known: nothing to read.
    @Test func knownCardIsNotRead() {
        var state = CardReadingState()
        let started = state.cardInReader(true, hasCertificates: true)
        #expect(!started)
        #expect(!state.isReading)
    }

    @Test func removalOrGivingUpEndsReading() {
        var removed = CardReadingState()
        _ = removed.cardInReader(true, hasCertificates: false)
        _ = removed.cardInReader(false, hasCertificates: false)
        #expect(!removed.isReading)

        var slow = CardReadingState()
        _ = slow.cardInReader(true, hasCertificates: false)
        slow.certificatesChanged(found: false)
        #expect(slow.isReading)
        slow.gaveUp()
        #expect(!slow.isReading)
    }
}
