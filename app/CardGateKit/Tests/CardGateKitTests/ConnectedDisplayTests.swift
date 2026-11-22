import CardGateKit
import Testing

struct ConnectedDisplayTests {
    let builtIn = ConnectedDisplay(name: "Built-in Retina Display", id: 1, key: ConnectedDisplay.builtInKey)
    static let dell = ConnectedDisplay.key(vendor: 4268, model: 9, serial: 0)
    let left = ConnectedDisplay(name: "DELL U2720Q (1)", id: 5, key: Self.dell)
    let right = ConnectedDisplay(name: "DELL U2720Q (2)", id: 6, key: Self.dell)

    /// The built-in display is found in another language too (its name changes, its key does not).
    @Test func builtInDisplayInAnotherLanguage() {
        let chosen = DisplayChoice(key: ConnectedDisplay.builtInKey, name: "Vestavěný displej Retina")
        #expect(ConnectedDisplay.display(for: chosen, among: [right, builtIn]) == builtIn)
    }

    /// A display with a serial number is found by it, whatever number macOS gives its name.
    @Test func displayWithSerialNumber() {
        let key = ConnectedDisplay.key(vendor: 4268, model: 9, serial: 1234)
        let renamed = ConnectedDisplay(name: "DELL U2720Q (1)", id: 8, key: key)
        let chosen = DisplayChoice(key: key, name: "DELL U2720Q (2)")
        #expect(ConnectedDisplay.display(for: chosen, among: [left, renamed]) == renamed)
    }

    /// Identical displays without a serial number are told apart by name.
    @Test func identicalDisplaysByName() {
        #expect(ConnectedDisplay.display(for: right.choice, among: [left, right]) == right)
        #expect(ConnectedDisplay.display(for: left.choice, among: [left, right]) == left)
    }

    /// The chosen one of identical displays without a serial number is unplugged: the main display,
    /// not its twin (now named without a number).
    @Test func identicalTwinIsNotTheChosenDisplay() {
        let twin = ConnectedDisplay(name: "DELL U2720Q", id: 5, key: Self.dell)
        #expect(ConnectedDisplay.display(for: right.choice, among: [builtIn, twin]) == nil)
    }

    /// Not connected (or no choice): the main display.
    @Test func notConnected() {
        #expect(ConnectedDisplay.display(for: right.choice, among: [builtIn]) == nil)
        #expect(ConnectedDisplay.display(for: nil, among: [builtIn, right]) == nil)
    }

    /// The settings offer the connected displays by their current name; the chosen one keeps its
    /// choice (the picker shows it) and is added, marked, when it is not connected.
    @Test func options() {
        let chosen = DisplayChoice(key: ConnectedDisplay.builtInKey, name: "Vestavěný displej Retina")
        let offered = ConnectedDisplay.options(chosen: chosen, among: [builtIn, right])
        #expect(
            offered == [
                .init(choice: chosen, name: "Built-in Retina Display"),
                .init(choice: right.choice, name: "DELL U2720Q (2)"),
            ])

        let away = ConnectedDisplay.options(chosen: right.choice, among: [builtIn])
        #expect(
            away == [
                .init(choice: builtIn.choice, name: builtIn.name),
                .init(choice: right.choice, name: right.name, isConnected: false),
            ])
        let none = ConnectedDisplay.options(chosen: nil, among: [builtIn])
        #expect(none == [.init(choice: builtIn.choice, name: builtIn.name)])
    }
}
