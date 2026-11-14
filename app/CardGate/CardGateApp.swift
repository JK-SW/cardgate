import CardGateKit
import OSLog
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
            // Its own process group: if the card driver hangs, CardGate stops it together with any
            // process the driver started (`CardMonitor.check`).
            setpgid(0, 0)
            print(PKCS11Probe.probe(module: module).encoded)
            exit(0)
        } else {
            if let running = SingleInstance.otherInstance() {
                // A second copy (another location, `open -n`) would share the log files, the
                // connections and the PIN dialog's notifications with the first one.
                SingleInstance.reopen(running)
                exit(0)
            }
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
                // A new or imported connection would become the selected one while another runs.
                Button("New Connection…") { model.beginNewProfile() }
                    .keyboardShortcut("n")
                    .disabled(model.isBusy)
                Button("Import .rdp File…") { model.isImportingRDP = true }
                    .keyboardShortcut("o")
                    .disabled(model.isBusy)
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

/// One CardGate per user session; the clients it started never outlive it (`InstancePolicy`).
@MainActor
enum SingleInstance {
    private static let logger = Logger(subsystem: "io.github.jk-sw.cardgate", category: "app")

    private static func running(_ bundleIdentifier: String) -> [(app: NSRunningApplication, info: RunningInstance)] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { !$0.isTerminated }
            .map { app in
                let info = RunningInstance(
                    pid: app.processIdentifier, isRegularApp: app.activationPolicy == .regular, bundleURL: app.bundleURL
                )
                return (app, info)
            }
    }

    static func otherInstance() -> NSRunningApplication? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        let candidates = running(identifier)
        let other = InstancePolicy.otherInstance(
            among: candidates.map(\.info), current: NSRunningApplication.current.processIdentifier)
        return candidates.first { $0.info.pid == other?.pid }?.app
    }

    /// Brings the running CardGate forward as if it was opened again (its window reappears even
    /// when closed). A plain `activate()` from a process that is not active is ignored.
    static func reopen(_ running: NSRunningApplication) {
        guard let url = running.bundleURL else { return }
        let done = DispatchSemaphore(value: 0)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, _ in
            done.signal()
        }
        _ = done.wait(timeout: .now() + 5)
    }

    /// Ends this app's clients left running after it crashed or was force quit: there is only one
    /// CardGate, so none of them belongs to a running app. They hold the redirected card.
    static func endOrphanedClients() {
        let app = Bundle.main.bundleURL
        guard let identifier = Bundle(url: FreeRDPCommand.clientApp(in: app))?.bundleIdentifier else { return }
        let clients = running(identifier)
        for orphan in InstancePolicy.orphanedClients(among: clients.map(\.info), app: app) {
            guard let client = clients.first(where: { $0.info.pid == orphan.pid })?.app else { continue }
            let pid = orphan.pid
            logger.error("Ending a client left running (pid \(pid))")
            Task {
                await ClientStop.run(
                    connected: true,
                    terminate: { kill(pid, SIGTERM) },
                    isRunning: { !client.isTerminated },
                    kill: { kill(pid, SIGKILL) })
            }
        }
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
            followSession()
        }
    }
    private var windows = SessionWindowPolicy()
    private let reconnectNotice = ReconnectNotice()
    /// Quitting waits for the client to end (`applicationShouldTerminate`).
    private var quit = PendingQuit()

    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix(WindowID.main) == true }
    }

    private func desktopShown() {
        windows.desktopShown()
        mainWindow?.orderOut(nil)
        // The client never activates itself (agent app).
        showDesktop()
    }

    /// Shows the reconnect notice while the session phase says so (re-registers after each change).
    private func followSession() {
        guard let session = model?.session else { return }
        let showsNotice = withObservationTracking {
            windows.showsReconnectNotice(phase: session.phase)
        } onChange: { [weak self] in
            Task { @MainActor in self?.followSession() }
        }
        if showsNotice {
            reconnectNotice.show(session: session)
        } else {
            reconnectNotice.hide()
        }
    }

    private func clientEnded() {
        if quit.isWaiting {
            finishQuit()
            return
        }
        guard windows.sessionEnded() else { return }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func showDesktop() {
        guard windows.isShowingDesktop, let client = model?.session.clientApplication else { return }
        NSApp.yieldActivation(to: client)
        client.activate()
    }

    func applicationDidFinishLaunching(_: Notification) {
        SingleInstance.endOrphanedClients()
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
        // The reconnect notice stays over the desktop; it is not a CardGate window to keep in front.
        let windowVisible = NSApp.windows.contains {
            $0.isVisible && ($0.canBecomeMain || $0.canBecomeKey) && $0 !== reconnectNotice.window
        }
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
        let session = model?.session
        switch quit.decide(sessionRunning: session?.isRunning == true) {
        case .quitNow: return .terminateNow
        case .keepWaiting: return .terminateLater  // e.g. logout while waiting for the client
        case .ask: break
        }
        guard let session else { return .terminateNow }
        // E.g. Quit in the Dock menu while the remote desktop is in front.
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit CardGate and disconnect?")
        alert.informativeText = String(localized: "The remote desktop connection will be closed.")
        alert.addButton(withTitle: String(localized: "Quit and Disconnect"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        let connected = session.phase?.hasDesktop == true
        session.stop()
        guard session.isRunning else { return .terminateNow }  // only the gateway check ran
        // The client is killed if it does not quit in time; the deadline is a last resort.
        quit.begin()
        Task { [weak self] in
            try? await Task.sleep(for: ClientStop.quitDeadline(connected: connected))
            self?.finishQuit()
        }
        return .terminateLater
    }

    private func finishQuit() {
        if quit.finish() { NSApp.reply(toApplicationShouldTerminate: true) }
    }
}
