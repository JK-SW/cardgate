@preconcurrency import CryptoTokenKit
import Foundation

/// Watches the card readers (CryptoTokenKit slots) to notice an inserted card at once – seconds
/// before the card's software offers its certificates. Needs the `com.apple.security.smartcard`
/// entitlement. Tokens that are not in a smart card reader are not seen here; for them nothing
/// changes.
@MainActor
final class CardReaderWatcher {
    /// Called with `true` when a card is in some reader (being read or readable), `false` when none.
    var onChange: ((Bool) -> Void)?

    private let manager = TKSmartCardSlotManager.default
    private var namesObservation: NSKeyValueObservation?
    private var slotObservations: [String: NSKeyValueObservation] = [:]
    private var states: [String: TKSmartCardSlot.State] = [:]
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
        let names = Set(manager.slotNames)
        for removed in Set(slotObservations.keys).subtracting(names) {
            slotObservations[removed] = nil
            states[removed] = nil
        }
        for name in names where slotObservations[name] == nil {
            Task { [weak self] in
                guard let slot = await manager.getSlot(withName: name), let self,
                    manager.slotNames.contains(name), slotObservations[name] == nil
                else { return }
                typealias StateHandler =
                    @Sendable (TKSmartCardSlot, NSKeyValueObservedChange<TKSmartCardSlot.State>) -> Void
                let handler: StateHandler = { [weak self] slot, _ in
                    let state = slot.state
                    Task { @MainActor in self?.slot(name, changedTo: state) }
                }
                slotObservations[name] = slot.observe(\.state, options: [.initial], changeHandler: handler)
            }
        }
        publish()
    }

    private func slot(_ name: String, changedTo state: TKSmartCardSlot.State) {
        // A change queued before the reader was unplugged must not bring its state back.
        guard slotObservations[name] != nil else { return }
        states[name] = state
        publish()
    }

    private func publish() {
        let present = states.values.contains { $0 == .probing || $0 == .validCard }
        guard present != cardPresent else { return }
        cardPresent = present
        onChange?(present)
    }
}
