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
            PINPrompt.run(prompt: arguments.dropFirst().joined(separator: " "))
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

    var body: some Scene {
        Window("CardGate", id: WindowID.main) {
            ContentView()
                .environment(model)
                .frame(minWidth: 460, minHeight: 420)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") { model.beginNewProfile() }
                    .keyboardShortcut("n")
                Button("Import .rdp File…") { model.isImportingRDP = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .windowArrangement) {
                OpenWindowButton(title: "Connection Log", id: WindowID.log)
                    .keyboardShortcut("l", modifiers: [.command, .option])
            }
        }

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
}

private struct OpenWindowButton: View {
    let title: LocalizedStringKey
    let id: String
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(title) { openWindow(id: id) }
    }
}
