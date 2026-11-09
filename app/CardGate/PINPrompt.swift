import AppKit
import CardGateKit

/// Native PIN dialog shown when FreeRDP needs the PIN of the smart card.
///
/// FreeRDP runs `CardGate --askpass '<prompt>'` (`FREERDP_ASKPASS`) and reads the PIN from
/// standard output. The PIN is never stored, logged or passed on a command line.
@MainActor
enum PINPrompt {
    static let argument = "--askpass"

    static var command: AskPassCommand {
        AskPassCommand(
            executable: Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0]),
            arguments: [argument])
    }

    static func run(prompt: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate()

        let alert = NSAlert()
        alert.messageText = String(localized: "Enter the PIN of your smart card")
        if let host = AskPassCommand.host(fromPrompt: prompt) {
            alert.informativeText =
                String(localized: "Signing in to \(host).") + "\n"
                + String(localized: "Several wrong attempts lock the card.")
        } else {
            alert.informativeText = String(localized: "Several wrong attempts lock the card.")
        }
        alert.icon =
            NSImage(systemSymbolName: "lock.rectangle", accessibilityDescription: nil)
            ?? app.applicationIconImage

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = String(localized: "PIN")
        field.setAccessibilityLabel(String(localized: "PIN"))
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Sign In"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.window.initialFirstResponder = field
        alert.window.level = .floating

        let response = alert.runModal()
        let pin = field.stringValue
        guard response == .alertFirstButtonReturn, !pin.isEmpty else { exit(1) }
        FileHandle.standardOutput.write(Data((pin + "\n").utf8))
        exit(0)
    }
}
