import AppKit
import CardGateKit
import SwiftUI

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

    /// Posted (as distributed notifications, without any data) so the app can show that the
    /// dialog is waiting for the PIN.
    nonisolated static let shownNotification = Notification.Name("io.github.jk-sw.cardgate.pin-prompt.shown")
    nonisolated static let closedNotification = Notification.Name("io.github.jk-sw.cardgate.pin-prompt.closed")

    private static func post(_ name: Notification.Name) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: nil, deliverImmediately: true)
    }

    static func run(prompt: String) -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        var pin: String?
        let window = NSWindow(
            contentRect: .zero, styleMask: [.titled, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.contentViewController = NSHostingController(
            rootView: PINPromptView(host: AskPassCommand.host(fromPrompt: prompt)) { result in
                pin = result
                app.stopModal()
            })
        placeOnScreenWithPointer(window)
        app.activate()
        window.makeKeyAndOrderFront(nil)
        post(shownNotification)
        app.runModal(for: window)
        post(closedNotification)

        guard let pin, !pin.isEmpty else { exit(1) }
        FileHandle.standardOutput.write(Data((pin + "\n").utf8))
        exit(0)
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
    let host: String?
    /// Called with the PIN, or `nil` when cancelled.
    let finish: (String?) -> Void

    @State private var pin = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.rectangle.stack.fill")
                .font(.system(size: 44))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Enter the PIN of your smart card")
                    .font(.headline)
                if let host {
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
                .onSubmit(submit)

            Text("Several wrong attempts lock the card.")
                .font(.footnote)
                .foregroundStyle(.secondary)

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
                .disabled(pin.isEmpty)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.top, 8)
        .padding(.bottom, 22)
        .frame(width: 320)
        .onAppear { focused = true }
    }

    private func submit() {
        guard !pin.isEmpty else { return }
        finish(pin)
    }
}
