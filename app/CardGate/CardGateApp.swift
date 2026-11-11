import CardGateKit
import SwiftUI

/// Entry point: the same executable is the app and, when FreeRDP starts it with `--askpass`,
/// the PIN dialog (see `PINPrompt`).
@main
@MainActor
enum Main {
    static func main() {
        #if DEBUG
            // Screenshots of the user guides are taken in light mode (scripts/screenshots.sh).
            if ProcessInfo.processInfo.environment["CARDGATE_APPEARANCE"] == "light" {
                NSApplication.shared.appearance = NSAppearance(named: .aqua)
            }
        #endif
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
    @State private var updater = Updater()
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
                if updater.isAvailable {
                    Button("Check for Updates…") { updater.checkForUpdates() }
                        .disabled(!updater.canCheckForUpdates)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") { model.beginNewProfile() }
                    .keyboardShortcut("n")
                Button("Import .rdp File…") { model.isImportingRDP = true }
                    .keyboardShortcut("o")
            }
            CommandGroup(replacing: .help) {
                Link(
                    "CardGate User Guide",
                    destination: ProjectLinks.userGuide(language: Bundle.main.preferredLocalizations.first))
                // No shortcut: ⌘? (⌘⇧/) belongs to the system's Help menu search.
                OpenWindowButton(title: "Keyboard Shortcuts", id: WindowID.shortcuts)
            }
            CommandGroup(after: .windowArrangement) {
                OpenWindowButton(title: "Connection Log", id: WindowID.log)
                    .keyboardShortcut("l", modifiers: [.command, .option])
            }
        }

        Settings {
            SettingsView(updater: updater)
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
///
/// The client runs as an agent app without a Dock icon, so CardGate stands for the connection
/// and shows one window at a time (see `SessionWindowPolicy`).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel? {
        didSet {
            model?.onDesktopShown = { [weak self] in self?.desktopShown() }
            model?.onClientEnded = { [weak self] in self?.clientEnded() }
        }
    }
    private var windows = SessionWindowPolicy()

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.main) == true }
    }

    private func desktopShown() {
        windows.desktopShown()
        mainWindow?.orderOut(nil)
        // The client never activates itself (agent app).
        showDesktop()
    }

    private func clientEnded() {
        guard windows.sessionEnded() else { return }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func showDesktop() {
        guard windows.isShowingDesktop, let client = model?.session.clientApplication else { return }
        NSApp.yieldActivation(to: client)
        client.activate()
    }

    func applicationDidBecomeActive(_: Notification) {
        // Only an active app can hand over activation, so this waits until the activation has
        // finished (next run loop turn).
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.forwardActivation() }
        }
    }

    /// Dock or app switcher while connected: the user wants the remote desktop.
    private func forwardActivation() {
        let windowVisible = NSApp.windows.contains { $0.isVisible && ($0.canBecomeMain || $0.canBecomeKey) }
        if windows.forwardsActivation(windowVisible: windowVisible, modalOpen: NSApp.modalWindow != nil) {
            showDesktop()
        }
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        switch windows.reopen(isActive: NSApp.isActive) {
        case .standard: return true
        case .showDesktop: showDesktop()
        case .nothing: break
        }
        return false
    }

    @objc private func disconnect() {
        model?.session.stop()
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        guard windows.isShowingDesktop else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: String(localized: "Disconnect"), action: #selector(disconnect), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        return menu
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard let session = model?.session, session.isRunning else { return .terminateNow }
        // E.g. Quit in the Dock menu while the remote desktop is in front.
        NSApp.activate()
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
