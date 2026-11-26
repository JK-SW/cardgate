import Foundation

/// The card readers (CryptoTokenKit slots) and the card in each, as `CardReaderWatcher` reports them:
/// which readers to look up, when to look again, and when a card was put in or taken out. Pure state,
/// fed by the watcher, so it can be tested without readers.
///
/// A token is a reader of its own: pulled, its slot goes "missing"; plugged in again, a new slot
/// appears under the same name. Pulled and plugged in again quickly, the list of readers may be
/// reported only once, unchanged – the old slot then stays missing for good, so a missing slot is
/// dropped and the reader looked up again, with growing pauses while it stays listed.
public struct ReaderSlots: Equatable, Sendable {
    /// `TKSmartCardSlot.State`.
    public enum State: Equatable, Sendable {
        case missing
        case empty
        case probing
        case muteCard
        case validCard

        /// A card is in the reader, being read or readable (a mute card is not usable).
        public var holdsCard: Bool { self == .probing || self == .validCard }

        /// A card is in the reader, also one that does not answer (e.g. for a moment after a reset):
        /// only taking it out is a removal.
        public var cardIn: Bool { holdsCard || self == .muteCard }
    }

    /// A card was put in a reader (`true`) or taken out, or the reader went away with it (`false`).
    public struct Change: Equatable, Sendable {
        public let reader: String
        public let cardIn: Bool

        public init(reader: String, cardIn: Bool) {
            self.reader = reader
            self.cardIn = cardIn
        }
    }

    /// The last state of each watched reader (none yet: just looked up).
    public private(set) var states: [String: State] = [:]
    /// Readers watched (their slot found), and readers being looked up.
    private var watched: Set<String> = []
    private var lookingUp: Set<String> = []
    /// Lookups in a row that found no usable slot, for the pause before the next one.
    private var failures: [String: Int] = [:]
    /// The longest pause between lookups of a reader that stays listed without a usable slot.
    public static let longestPause: Duration = .seconds(30)

    public init() {}

    /// A card is in some reader, being read or readable.
    public var cardPresent: Bool { states.values.contains(where: \.holdsCard) }

    /// The reader's slot is watched (found and not gone since).
    public func isWatched(_ name: String) -> Bool { watched.contains(name) }

    /// The list of readers changed (or is looked at again): readers gone are forgotten (a card in
    /// them is taken out), readers new or not watched are to be looked up.
    public mutating func listed(_ names: Set<String>) -> (changes: [Change], lookUp: [String]) {
        var changes: [Change] = []
        for gone in watched.subtracting(names).sorted() {
            if states[gone]?.cardIn == true { changes.append(Change(reader: gone, cardIn: false)) }
            watched.remove(gone)
            states[gone] = nil
        }
        failures = failures.filter { names.contains($0.key) }
        let lookUp = names.subtracting(watched).subtracting(lookingUp).sorted()
        lookingUp.formUnion(lookUp)
        return (changes, lookUp)
    }

    /// The lookup of a reader ended. - Returns: whether to watch the slot found (the reader is still
    /// listed); when `nil`, the pause before looking again.
    public mutating func lookedUp(_ name: String, found: Bool, stillListed: Bool) -> Duration? {
        lookingUp.remove(name)
        guard stillListed else { return nil }
        guard found else { return failed(name) }
        watched.insert(name)
        return nil
    }

    /// A watched reader's state. - Returns: the card's change, if any, and the pause before looking
    /// the reader up again when its slot went missing (`.zero`: at once).
    public mutating func reader(_ name: String, changedTo state: State) -> (change: Change?, lookAgain: Duration?) {
        // A state queued before the reader was forgotten must not bring it back.
        guard watched.contains(name) else { return (nil, nil) }
        let had = states[name]
        if state == .missing {
            watched.remove(name)
            states[name] = nil
            let change = had?.cardIn == true ? Change(reader: name, cardIn: false) : nil
            // Missing after it was there: the reader went away, a new slot may be listed already.
            // Missing at once: looked up too early, look again after a pause.
            guard had != nil else { return (change, failed(name)) }
            failures[name] = nil
            return (change, .zero)
        }
        states[name] = state
        failures[name] = nil
        // The first state of a reader is no change, unless it already holds a card (plugged in with one).
        let changed = had.map { $0.cardIn != state.cardIn } ?? state.cardIn
        return (changed ? Change(reader: name, cardIn: state.cardIn) : nil, nil)
    }

    /// 1, 2, 4, 8, 16, then 30 s.
    private mutating func failed(_ name: String) -> Duration {
        let count = failures[name, default: 0]
        failures[name] = count + 1
        return min(.seconds(1 << min(count, 5)), Self.longestPause)
    }

    /// The reader `reader` is redirected to the computer by FreeRDP's filter (`/smartcard:<filter>`:
    /// readers whose name contains it). Without a filter every reader is: which one holds the
    /// session's card is not known, so none is.
    public static func isRedirected(_ reader: String, filter: String?) -> Bool {
        guard let filter, !filter.isEmpty else { return false }
        return reader.contains(filter)
    }
}
