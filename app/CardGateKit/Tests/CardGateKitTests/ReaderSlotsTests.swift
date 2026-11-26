import Foundation
import Testing

@testable import CardGateKit

/// The card readers and the card in each (`CardReaderWatcher`), without readers.
struct ReaderSlotsTests {
    typealias Change = ReaderSlots.Change

    /// A reader listed, looked up and watched.
    static func watching(_ name: String = "Reader") -> ReaderSlots {
        var slots = ReaderSlots()
        _ = slots.listed([name])
        _ = slots.lookedUp(name, found: true, stillListed: true)
        return slots
    }

    @Test func cardPutInAndTakenOut() {
        var slots = Self.watching()
        #expect(slots.reader("Reader", changedTo: .empty).change == nil)  // the first state is no change
        #expect(slots.reader("Reader", changedTo: .probing).change == Change(reader: "Reader", cardIn: true))
        #expect(slots.cardPresent)
        #expect(slots.reader("Reader", changedTo: .validCard).change == nil)
        // A card that does not answer for a moment is still in.
        #expect(slots.reader("Reader", changedTo: .muteCard).change == nil)
        #expect(!slots.cardPresent)
        #expect(slots.reader("Reader", changedTo: .empty).change == Change(reader: "Reader", cardIn: false))
    }

    /// A reader plugged in with a card (a token) reports it at once.
    @Test func pluggedInWithACard() {
        var slots = Self.watching()
        #expect(slots.reader("Reader", changedTo: .validCard).change == Change(reader: "Reader", cardIn: true))
    }

    /// A token pulled: its reader leaves the list with the card.
    @Test func readerUnplugged() {
        var slots = Self.watching()
        _ = slots.reader("Reader", changedTo: .validCard)
        let (changes, lookUp) = slots.listed([])
        #expect(changes == [Change(reader: "Reader", cardIn: false)])
        #expect(lookUp.isEmpty)
        #expect(!slots.isWatched("Reader"))
        // A state queued before does not bring it back.
        #expect(slots.reader("Reader", changedTo: .validCard).change == nil)
    }

    /// Pulled and plugged in again quickly, the list looks unchanged: the old slot goes missing, the
    /// reader is looked up again at once and its new slot reports the card.
    @Test func tokenPluggedInAgainQuickly() {
        var slots = Self.watching()
        _ = slots.reader("Reader", changedTo: .validCard)
        let missing = slots.reader("Reader", changedTo: .missing)
        #expect(missing.change == Change(reader: "Reader", cardIn: false))
        #expect(missing.lookAgain == .zero)
        #expect(slots.listed(["Reader"]).lookUp == ["Reader"])
        #expect(slots.lookedUp("Reader", found: true, stillListed: true) == nil)
        #expect(slots.reader("Reader", changedTo: .validCard).change == Change(reader: "Reader", cardIn: true))
    }

    /// A slot missing at once, or not found, is looked up again with growing pauses while the reader
    /// stays listed; no longer listed, it is forgotten.
    @Test func lookedUpAgainWithGrowingPauses() {
        var slots = ReaderSlots()
        _ = slots.listed(["Reader"])
        #expect(slots.lookedUp("Reader", found: false, stillListed: true) == .seconds(1))
        _ = slots.listed(["Reader"])
        _ = slots.lookedUp("Reader", found: true, stillListed: true)
        #expect(slots.reader("Reader", changedTo: .missing).lookAgain == .seconds(2))
        var pauses: [Duration] = []
        for _ in 0..<5 {
            _ = slots.listed(["Reader"])
            pauses.append(slots.lookedUp("Reader", found: false, stillListed: true) ?? .zero)
        }
        #expect(pauses == [.seconds(4), .seconds(8), .seconds(16), .seconds(30), .seconds(30)])
        // Found and reporting a state: the pauses start again.
        _ = slots.listed(["Reader"])
        _ = slots.lookedUp("Reader", found: true, stillListed: true)
        _ = slots.reader("Reader", changedTo: .empty)
        _ = slots.listed(["Reader"])
        _ = slots.reader("Reader", changedTo: .missing)
        _ = slots.listed(["Reader"])
        #expect(slots.lookedUp("Reader", found: false, stillListed: true) == .seconds(1))
        // Gone from the list: nothing to look for.
        _ = slots.listed([])
        #expect(slots.lookedUp("Reader", found: false, stillListed: false) == nil)
    }

    /// A reader being looked up is not looked up twice.
    @Test func noDoubleLookup() {
        var slots = ReaderSlots()
        #expect(slots.listed(["A", "B"]).lookUp == ["A", "B"])
        #expect(slots.listed(["A", "B"]).lookUp.isEmpty)
    }

    /// Only the reader FreeRDP redirects; without a filter none (which one holds the card is unknown).
    @Test func redirectedReader() {
        #expect(ReaderSlots.isRedirected("Example USB Reader 01", filter: "Example USB Reader"))
        #expect(!ReaderSlots.isRedirected("Other Reader", filter: "Example USB Reader"))
        #expect(!ReaderSlots.isRedirected("Example USB Reader", filter: nil))
        #expect(!ReaderSlots.isRedirected("Example USB Reader", filter: ""))
    }
}
