import SwiftUI

@main
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
