import CardGateKit
import SwiftUI

/// Entry point: the same executable is the app and, when FreeRDP starts it with `--askpass`,
/// the PIN dialog (see `PINPrompt`).
@main
@MainActor
enum Main {
    static func main() {
        let arguments = CommandLine.arguments.dropFirst()
        if arguments.first == PINPrompt.argument {
            PINPrompt.run(arguments: Array(arguments.dropFirst()))
        } else if arguments.first == CardMonitor.checkArgument, let module = arguments.dropFirst().first {
            // Separate short-lived process: the middleware is loaded fresh and never stays in the app.
            print(PKCS11Probe.probe(module: module).encoded)
            exit(0)
        } else {
            CardGateApp.main()
        }
    }
}

struct CardGateApp: App {
    @State private var model = AppModel()
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate

    var body: some Scene {
        Window("CardGate", id: WindowID.main) {
            ContentView()
                .environment(model)
                .onAppear { delegate.model = model }
                .frame(width: 440)
                .fixedSize(horizontal: false, vertical: true)
        }
        // The window always fits its content; there is nothing to gain from a bigger one.
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) {
                OpenWindowButton(title: "About CardGate", id: WindowID.about)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") { model.beginNewProfile() }
                    .keyboardShortcut("n")
                Button("Import .rdp File…") { model.isImportingRDP = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .help) {
                OpenWindowButton(title: "Keyboard Shortcuts", id: WindowID.shortcuts)
                    .keyboardShortcut("/", modifiers: [.command, .shift])
            }
            CommandGroup(after: .windowArrangement) {
                OpenWindowButton(title: "Connection Log", id: WindowID.log)
                    .keyboardShortcut("l", modifiers: [.command, .option])
            }
        }

        Window("Keyboard Shortcuts", id: WindowID.shortcuts) {
            KeyboardShortcutsView()
        }
        .windowResizability(.contentSize)

        Window("About CardGate", id: WindowID.about) {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Window("Connection Log", id: WindowID.log) {
            LogView()
                .environment(model)
                .frame(minWidth: 600, minHeight: 300)
        }
        .defaultSize(width: 800, height: 450)
    }
}

enum WindowID {
    static let main = "main"
    static let log = "log"
    static let about = "about"
    static let shortcuts = "shortcuts"
}

private struct OpenWindowButton: View {
    let title: LocalizedStringKey
    let id: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) { openWindow(id: id) }
    }
}

/// Asks before quitting while a connection is open, and ends that connection then – a client
/// left running without the app would have no status, log or PIN dialog guard.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard let session = model?.session, session.isRunning else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit CardGate and disconnect?")
        alert.informativeText = String(localized: "The remote desktop connection will be closed.")
        alert.addButton(withTitle: String(localized: "Quit and Disconnect"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        session.stop()
        return .terminateNow
    }
}
