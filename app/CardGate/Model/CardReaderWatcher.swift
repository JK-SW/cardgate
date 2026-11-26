import CardGateKit
@preconcurrency import CryptoTokenKit
import Foundation

/// Watches the card readers (CryptoTokenKit slots) to notice an inserted card at once – seconds
/// before the card's software offers its certificates. Needs the `com.apple.security.smartcard`
/// entitlement. Tokens that are not in a smart card reader are not seen here; for them nothing
/// changes. What it means is decided by `ReaderSlots`; this class only feeds it the system's reports.
@MainActor
final class CardReaderWatcher {
    /// Called with `true` when a card is in some reader (being read or readable), `false` when none.
    var onChange: ((Bool) -> Void)?
    /// Called with a reader's name when a card was put in it (`true`) or taken out, or the reader
    /// was unplugged with a card (`false`).
    var onReaderChange: ((String, Bool) -> Void)?

    private let manager = TKSmartCardSlotManager.default
    private var namesObservation: NSKeyValueObservation?
    private var slotObservations: [String: NSKeyValueObservation] = [:]
    private var slots = ReaderSlots()
    private var cardPresent = false

    init() {
        // CryptoTokenKit reports changes on its own queue: the handlers must not be main actor
        // isolated (Swift would trap), so they are @Sendable and hop to the main actor.
        typealias NamesHandler = @Sendable (TKSmartCardSlotManager, NSKeyValueObservedChange<[String]>) -> Void
        let handler: NamesHandler = { [weak self] _, _ in
            Task { @MainActor in self?.updateSlots() }
        }
        namesObservation = manager?.observe(\.slotNames, options: [.initial], changeHandler: handler)
    }

    private func updateSlots() {
        guard let manager else { return }
        let (changes, lookUp) = slots.listed(Set(manager.slotNames))
        dropForgottenObservations()
        report(changes)
        for name in lookUp {
            Task { [weak self] in
                let slot = await manager.getSlot(withName: name)
                guard let self else { return }
                let pause = slots.lookedUp(name, found: slot != nil, stillListed: manager.slotNames.contains(name))
                if let pause {
                    lookAgain(after: pause)
                } else if let slot, slots.isWatched(name) {
                    observe(slot, named: name)
                }
            }
        }
    }

    private func observe(_ slot: TKSmartCardSlot, named name: String) {
        typealias StateHandler = @Sendable (TKSmartCardSlot, NSKeyValueObservedChange<TKSmartCardSlot.State>) -> Void
        let handler: StateHandler = { [weak self] slot, _ in
            let state = slot.state
            Task { @MainActor in self?.slot(name, changedTo: state) }
        }
        slotObservations[name] = slot.observe(\.state, options: [.initial], changeHandler: handler)
    }

    private func slot(_ name: String, changedTo state: TKSmartCardSlot.State) {
        let (change, pause) = slots.reader(name, changedTo: Self.state(state))
        dropForgottenObservations()
        report(change.map { [$0] } ?? [])
        if let pause { lookAgain(after: pause) }
    }

    /// Looks at the list of readers again (a reader whose slot went missing may be listed anew).
    private func lookAgain(after pause: Duration) {
        guard pause > .zero else {
            updateSlots()
            return
        }
        Task { [weak self] in
            try? await Task.sleep(for: pause)
            self?.updateSlots()
        }
    }

    private func dropForgottenObservations() {
        for name in slotObservations.keys where !slots.isWatched(name) {
            slotObservations[name] = nil
        }
    }

    private func report(_ changes: [ReaderSlots.Change]) {
        for change in changes { onReaderChange?(change.reader, change.cardIn) }
        guard slots.cardPresent != cardPresent else { return }
        cardPresent = slots.cardPresent
        onChange?(cardPresent)
    }

    private static func state(_ state: TKSmartCardSlot.State) -> ReaderSlots.State {
        switch state {
        case .missing: .missing
        case .empty: .empty
        case .probing: .probing
        case .muteCard: .muteCard
        case .validCard: .validCard
        @unknown default: .empty
        }
    }
}
