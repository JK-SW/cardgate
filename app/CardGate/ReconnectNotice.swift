import AppKit
import CardGateKit
import SwiftUI

/// A small panel over the remote desktop while the client reconnects after an outage: the desktop
/// keeps its last picture and does not respond meanwhile, and CardGate's window is hidden.
///
/// It never takes the focus from the remote desktop (non-activating), also shows over a desktop in
/// full screen and is only on screen while the desktop is in front
/// (`SessionWindowPolicy.reconnectNoticeVisible`).
@MainActor
final class ReconnectNotice {
    private var panel: NSPanel?
    private var client: pid_t?
    /// The desktop window, once found: later checks ask the window server for this one only.
    private var desktopWindow: CGWindowID?
    /// Keeps the notice in the middle of the desktop window while the user moves it, and shows or
    /// hides it (the window belongs to the client process, so it cannot be a child window of
    /// CardGate's panel, and macOS reports its moves only through the Accessibility API).
    private var follow: Timer?
    private var pace = NoticeFollowPace()

    var window: NSWindow? { panel }

    func show(session: SessionController) {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered, defer: true)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.isMovable = false  // it follows the desktop window
        panel.isReleasedWhenClosed = false
        // CardGate is not the active app; the panel must stay over the desktop anyway.
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: ReconnectNoticeView(session: session))
        panel.setContentSize(panel.contentView?.fittingSize ?? .zero)
        self.panel = panel
        client = session.clientApplication?.processIdentifier
        desktopWindow = nil
        pace = NoticeFollowPace()
        update()
        scheduleFollow()
    }

    func hide() {
        follow?.invalidate()
        follow = nil
        panel?.orderOut(nil)
        panel = nil
        client = nil
    }

    private func scheduleFollow() {
        follow?.invalidate()
        let timer = Timer(timeInterval: pace.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        follow = timer
    }

    private func update() {
        guard let panel, let client else { return }
        let window = locate(client)
        let clientActive = NSWorkspace.shared.frontmostApplication?.processIdentifier == client
        var moved = false
        if SessionWindowPolicy.reconnectNoticeVisible(window: window, clientActive: clientActive),
            let window, let mainDisplay = NSScreen.screens.first
        {
            let origin = SessionWindowPolicy.reconnectNoticeOrigin(
                window: window.frame, mainDisplayHeight: mainDisplay.frame.height, size: panel.frame.size)
            moved = origin != panel.frame.origin
            if moved { panel.setFrameOrigin(origin) }
            if !panel.isVisible { panel.orderFrontRegardless() }
        } else if panel.isVisible {
            panel.orderOut(nil)
        }
        if pace.checked(moved: moved, now: ProcessInfo.processInfo.systemUptime) { scheduleFollow() }
    }

    /// The desktop window: the one found before if it still exists, otherwise searched among all
    /// windows (also minimized ones).
    private func locate(_ client: pid_t) -> DesktopWindow? {
        if let number = desktopWindow,
            let window = DesktopWindow.window(number, of: client, in: Self.windowList(.optionIncludingWindow, number))
        {
            return window
        }
        let window = DesktopWindow.find(of: client, in: Self.windowList([.optionAll, .excludeDesktopElements]))
        desktopWindow = window?.number
        return window
    }

    private static func windowList(_ options: CGWindowListOption, _ window: CGWindowID = kCGNullWindowID)
        -> [[String: Any]]
    {
        CGWindowListCopyWindowInfo(options, window) as? [[String: Any]] ?? []
    }
}

private struct ReconnectNoticeView: View {
    let session: SessionController

    var body: some View {
        VStack(spacing: 14) {
            SessionStatusView(phase: session.phase, stopping: session.isStopping)
            Text("The remote desktop does not respond until the connection is restored.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(role: .destructive) {
                session.stop()
            } label: {
                Text("Disconnect").frame(minWidth: 120)
            }
            .controlSize(.large)
            .disabled(session.isStopping)
            .accessibilityIdentifier("reconnectDisconnect")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 380)
    }
}
