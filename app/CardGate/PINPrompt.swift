import AppKit
import CardGateKit
import SwiftUI

/// Native PIN dialog shown when FreeRDP needs the PIN of the smart card.
///
/// FreeRDP runs `CardGate --askpass --module <pkcs11> '<prompt>'` (`FREERDP_ASKPASS`) and reads
/// the PIN from standard output. The PIN is never stored, logged or passed on a command line.
///
/// Every PIN the card rejects counts towards locking it, so the dialog guards against accidental
/// input (`PINEntryGuard`: typing and Enter meant for another app right when it appears), only
/// PINs of the length the card accepts can be sent, and the remaining attempts reported by the
/// card are shown.
@MainActor
enum PINPrompt {
    static let argument = "--askpass"
    static let moduleArgument = "--module"

    static func command(module: String) -> AskPassCommand {
        AskPassCommand(
            executable: Bundle.main.executableURL ?? URL(filePath: CommandLine.arguments[0]),
            arguments: [argument, moduleArgument, module])
    }

    /// Without a PIN for this long the dialog gives up (the gateway closes idle connections).
    static let timeout: Duration = .seconds(120)

    /// What happens to the dialog; posted as distributed notifications without any data so the
    /// app can show the right status.
    enum Event: String, CaseIterable, Sendable {
        case shown, submitted, cancelled, timedOut

        nonisolated var notification: Notification.Name {
            Notification.Name("io.github.jk-sw.cardgate.pin-prompt.\(rawValue)")
        }
    }

    private static func post(_ event: Event) {
        DistributedNotificationCenter.default().postNotificationName(
            event.notification, object: nil, userInfo: nil, deliverImmediately: true)
    }

    /// Closes the dialog when the RDP client that asked for the PIN goes away (disconnect, crash).
    private static func exitWithParent() -> any DispatchSourceProcess {
        let source = DispatchSource.makeProcessSource(identifier: getppid(), eventMask: .exit, queue: .main)
        source.setEventHandler { quit(1) }
        source.resume()
        return source
    }

    /// Ends the dialog process at once. `exit` would run the cleanup handlers of the loaded
    /// libraries while the card's PIN limits may still be read on another thread; the PKCS#11
    /// module then crashes, and the RDP client takes the crash for a cancelled dialog. The PIN is
    /// already written (`FileHandle.write` is unbuffered), so nothing needs flushing.
    private static func quit(_ code: Int32) -> Never {
        _exit(code)
    }

    /// - Parameter arguments: the arguments after `--askpass`.
    static func run(arguments: [String]) -> Never {
        var arguments = arguments
        var module: String?
        if arguments.first == moduleArgument, arguments.count >= 2 {
            module = arguments[1]
            arguments.removeFirst(2)
        }
        // FreeRDP passes the prompt as one quoted word; options after it (e.g. -AppleLanguages for
        // screenshots) are for AppKit, not part of the prompt.
        let prompt = arguments.prefix { !$0.hasPrefix("-") }.joined(separator: " ")

        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let parentWatch = exitWithParent()

        let model = PINPromptModel(host: AskPassCommand.host(fromPrompt: prompt))
        var pin: String?
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.contentViewController = NSHostingController(
            rootView: PINPromptView(model: model) { result in
                pin = result
                app.stopModal()
            })
        placeOnScreenWithPointer(window)
        app.activate()
        window.makeKeyAndOrderFront(nil)
        model.start(module: module)
        var timedOut = false
        let timer = Task {
            try? await Task.sleep(for: timeout)
            timedOut = true
            app.stopModal()
        }
        post(.shown)
        app.runModal(for: window)
        timer.cancel()
        parentWatch.cancel()

        guard !timedOut else {
            post(.timedOut)
            quit(1)
        }
        guard let pin, model.policy.accepts(pin) else {
            post(.cancelled)
            quit(1)
        }
        post(.submitted)
        FileHandle.standardOutput.write(Data((pin + "\n").utf8))
        quit(0)
    }
}

/// State of the PIN dialog.
@MainActor
@Observable
final class PINPromptModel {
    let host: String?
    /// Limits and remaining attempts as reported by the card (read without a PIN, takes seconds).
    private(set) var policy = PINPolicy.unknown
    private(set) var policyKnown = false
    /// When the dialog appeared (see `PINEntryGuard`).
    private(set) var entryGuard = PINEntryGuard()
    /// `entryGuard` accepts Enter (redraws the Sign In button when it does).
    private(set) var armed = false

    init(host: String?) {
        self.host = host
    }

    /// A keystroke typed now is kept (see `PINEntryGuard`).
    func acceptsTyping() -> Bool {
        entryGuard.acceptsTyping()
    }

    func start(module: String?) {
        entryGuard = PINEntryGuard()
        Task {
            try? await Task.sleep(for: PINEntryGuard.blockSubmitFor)
            armed = true
        }
        guard let module else { return }
        Task {
            let policy = await Task.detached { PKCS11Probe.pinPolicy(module: module) }.value
            if let policy {
                self.policy = policy
                policyKnown = true
            }
        }
    }
}

/// Centers the dialog on the display with the mouse pointer – where the user just clicked
/// Connect – instead of the main display, so it is not missed on another monitor.
@MainActor
private func placeOnScreenWithPointer(_ window: NSWindow) {
    window.layoutIfNeeded()
    let pointer = NSEvent.mouseLocation
    guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }) ?? NSScreen.main
    else {
        window.center()
        return
    }
    let visible = screen.visibleFrame
    let size = window.frame.size
    window.setFrameOrigin(
        NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2 + visible.height / 6))
}

private struct PINPromptView: View {
    let model: PINPromptModel
    /// Called with the PIN, or `nil` when cancelled.
    let finish: (String?) -> Void

    @State private var pin = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(
                systemName: model.policy.locked
                    ? "lock.trianglebadge.exclamationmark.fill" : "lock.rectangle.stack.fill"
            )
            .font(.system(size: 44))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(model.policy.locked ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
            .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Enter the PIN of your smart card")
                    .font(.headline)
                if let host = model.host {
                    Text("Signing in to \(host).")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)

            SecureField("PIN", text: $pin)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .frame(width: 220)
                .disabled(model.policy.locked)
                .onSubmit(submit)
                .onChange(of: pin) { _, new in
                    // Typing faster than anyone can react to the new dialog was meant for another app.
                    if !new.isEmpty, !model.acceptsTyping() { pin = "" }
                }

            attemptsInfo
                .font(.footnote)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button(role: .cancel) {
                    finish(nil)
                } label: {
                    Text("Cancel").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.cancelAction)
                Button(action: submit) {
                    Text("Sign In").frame(maxWidth: .infinity)
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(width: 320)
        .onAppear { focused = true }
    }

    @ViewBuilder private var attemptsInfo: some View {
        let policy = model.policy
        if policy.locked {
            Text("The card is locked. Unlock it with the PUK or contact your IT department.")
                .foregroundStyle(.red)
        } else if policy.finalTry {
            Text("Last attempt! Another wrong PIN locks the card.")
                .foregroundStyle(.red)
                .fontWeight(.semibold)
        } else if policy.countLow {
            Text("A wrong PIN was entered before. Only a few attempts remain.")
                .foregroundStyle(.orange)
        } else if model.policyKnown {
            Text(
                "The PIN has \(policy.minLength)–\(policy.maxLength) characters. Several wrong attempts lock the card."
            )
            .foregroundStyle(.secondary)
        } else {
            Text("Several wrong attempts lock the card.")
                .foregroundStyle(.secondary)
        }
    }

    private var canSubmit: Bool { model.armed && model.entryGuard.acceptsSubmit() && model.policy.accepts(pin) }

    private func submit() {
        guard canSubmit else { return }
        finish(pin)
    }
}
