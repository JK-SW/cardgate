import CardGateKit
import Testing

extension FreeRDPCommandTests {
    /// Full screen opens on the chosen display while it is connected, otherwise on the main one.
    @Test func fullScreenOnTheChosenDisplay() throws {
        let dell = ConnectedDisplay.key(vendor: 4268, model: 41234, serial: 0)
        let displays = [
            ConnectedDisplay(name: "Built-in Retina Display", id: 1, key: ConnectedDisplay.builtInKey),
            .init(name: "DELL U2720Q", id: 731, key: dell),
        ]
        func variable(_ display: DisplaySettings) throws -> String? {
            try FreeRDPCommand(
                executable: client, profile: profile(display: display), pkcs11Module: module, config: config,
                displays: displays
            ).environment[FreeRDPCommand.displayVariable]
        }
        let chosen = DisplayChoice(key: dell, name: "DELL U2720Q")
        #expect(try variable(.init(mode: .fullScreen, fullScreenDisplay: chosen)) == "731")
        let other = DisplayChoice(key: ConnectedDisplay.key(vendor: 1552, model: 1, serial: 7), name: "LG")
        #expect(try variable(.init(mode: .fullScreen, fullScreenDisplay: other)) == nil)
        #expect(try variable(.init(mode: .fullScreen)) == nil)
        #expect(try variable(.init(mode: .allDisplays, fullScreenDisplay: chosen)) == nil)
        #expect(try variable(.init(mode: .window, fullScreenDisplay: chosen)) == nil)
    }
}
