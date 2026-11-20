import CardGateKit
import SwiftUI

/// Main window: the connections in the sidebar, the selected one with the card, status and Connect.
struct ConnectView: View {
    /// The sidebar can be hidden (e.g. with one connection); a button in the toolbar shows it again.
    @State private var columns = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            ConnectionSidebar()
                // Both: SwiftUI on macOS ignores the column width alone.
                .frame(minWidth: ConnectionSidebar.minimumWidth)
                .navigationSplitViewColumnWidth(
                    min: ConnectionSidebar.minimumWidth, ideal: ConnectionSidebar.minimumWidth,
                    max: ConnectionSidebar.maximumWidth
                )
                .toolbar(removing: .sidebarToggle)
        } detail: {
            ConnectionDetail()
                // Dragging the sidebar wider must not squeeze the overview and the notices.
                .frame(minWidth: ConnectionDetailWidth.minimum)
                .navigationSplitViewColumnWidth(
                    min: ConnectionDetailWidth.minimum, ideal: ConnectionDetailWidth.minimum
                )
                .toolbar {
                    if columns == .detailOnly {
                        ToolbarItem(placement: .navigation) {
                            Button {
                                withAnimation { columns = .all }
                            } label: {
                                Label("Show Connections", systemImage: "sidebar.left")
                            }
                            .help("Show Connections")
                            .accessibilityIdentifier("toolbar.showSidebar")
                        }
                    }
                    AppToolbar()
                }
        }
        // The name of the connection is shown in the detail.
        .toolbar(removing: .title)
    }
}

/// The room the selected connection's details need: the overview and the notices with margins.
enum ConnectionDetailWidth {
    /// The overview, the notices and Connect.
    static let content: CGFloat = 440
    static let margin: CGFloat = 32
    static let minimum = content + 2 * margin
}

/// The windows a user looks for in the main window (also in the menus).
struct AppToolbar: ToolbarContent {
    @Environment(\.openWindow) private var openWindow

    var body: some ToolbarContent {
        // Keeps the buttons on the right.
        if #available(macOS 26, *) {
            ToolbarSpacer(.flexible)
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                openWindow(id: WindowID.log)
            } label: {
                Label("Connection Log", systemImage: "doc.text.magnifyingglass")
            }
            .help("Connection Log")
            .accessibilityIdentifier("toolbar.log")

            Button {
                openWindow(id: WindowID.shortcuts)
            } label: {
                Label("Keyboard Shortcuts", systemImage: "keyboard")
            }
            .help("Keyboard Shortcuts")
            .accessibilityIdentifier("toolbar.shortcuts")
        }
    }
}

/// The selected connection: where it goes, whether everything is ready, the progress and Connect,
/// together in the middle of the window.
private struct ConnectionDetail: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let profile = model.selectedProfile {
            let readiness = model.cardReadiness
            FillingScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    content(profile, readiness: readiness)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, ConnectionDetailWidth.margin)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
    }

    private func content(_ profile: ConnectionProfile, readiness: CardReadiness) -> some View {
        let running = model.session.isRunning
        // While connecting, the steps take the place of the overview.
        let connecting = model.session.phase?.connectionStep != nil
        return VStack(spacing: 14) {
            header(profile)
            if !connecting {
                ConnectionOverview(profile: profile, readiness: readiness)
            }
            VStack(spacing: 10) {
                if profile.gateway == nil {
                    MissingGatewayView(profile: profile)
                }
                SessionStatusView(phase: model.session.phase, stopping: model.session.isStopping)
                if !running {
                    GatewayStatusView()
                    CardNoticeView(readiness: readiness)
                }
            }
            .animation(.default, value: model.signInCertificate)
            if model.showsDonationOffer && !running {
                DonationOfferView()
                    .transition(.opacity)
            }
            ConnectButton()
                .padding(.top, 4)
        }
        .frame(maxWidth: ConnectionDetailWidth.content)
    }

    private func header(_ profile: ConnectionProfile) -> some View {
        HStack(spacing: 16) {
            AppIllustration(width: 76)
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                    .font(.title.weight(.bold))
                    .accessibilityIdentifier("detail.name")
                Text(profile.computer.description)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("detail.computer")
            }
            .lineLimit(2)
        }
        // Centered like the overview card and the button below it.
        .frame(maxWidth: .infinity)
    }
}

private struct ConnectButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.session.isRunning {
            // Until the desktop is shown there is nothing to disconnect: the attempt is cancelled.
            let connected = model.session.phase?.hasDesktop == true
            Button(role: .destructive) {
                model.session.stop()
            } label: {
                Text(connected ? "Disconnect" : "Cancel").frame(minWidth: 220)
            }
            .controlSize(.extraLarge)
            .disabled(model.session.isStopping)
            .accessibilityIdentifier("disconnect")
        } else {
            Button {
                model.connect()
            } label: {
                Group {
                    if model.isPreparingConnection {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .frame(minWidth: 220)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.isReadyToConnect)
            .accessibilityIdentifier("connect")
        }
    }
}

/// A connection saved by an older version without a gateway: CardGate connects only through one.
private struct MissingGatewayView: View {
    @Environment(AppModel.self) private var model
    let profile: ConnectionProfile

    var body: some View {
        NoticeView(
            tone: .warning, systemImage: "exclamationmark.shield.fill", title: Text("The connection has no gateway"),
            message: Text(
                "CardGate connects only through an RD Gateway, which protects the connection and your PIN.")
        ) {
            Button("Edit Connection") { model.beginEditing(profile) }
                .disabled(model.isBusy)
                .padding(.top, 4)
                .accessibilityIdentifier("missingGateway.edit")
        }
        .accessibilityIdentifier("missingGateway")
    }
}

/// A problem with the gateway found while idle (the chip shows when it is fine).
private struct GatewayStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Not next to a failure that already says the gateway is unreachable; after an interrupted
        // connection it shows whether the network is back.
        if model.shownGatewayStatus == .unreachable {
            NoticeView(
                tone: .warning, systemImage: "wifi.exclamationmark",
                title: Text(
                    "The gateway cannot be reached. Check your internet connection and the gateway address."))
        }
    }
}

/// Human readable connection progress and errors with advice.
struct SessionStatusView: View {
    let phase: SessionPhase?
    /// Cancel or Disconnect was chosen and the client is quitting.
    var stopping = false

    var body: some View {
        if stopping {
            NoticeView(
                tone: .neutral, systemImage: nil,
                title: phase?.hasDesktop == true ? Text("Disconnecting…") : Text("Cancelling…"), inProgress: true)
        } else if let phase {
            switch phase {
            case .ended(.closedByUser):
                EmptyView()
            case .starting, .waitingForPIN, .authenticatingGateway, .connectingComputer:
                ConnectionStepsView(phase: phase)
            case .connected:
                Label {
                    Text("Connected")
                } icon: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(StatusTone.success.background, in: Capsule())
            case .reconnecting:
                NoticeView(
                    tone: .info, systemImage: nil, title: Text("The connection was interrupted. Reconnecting…"),
                    inProgress: true)
            case .ended(.failed(let failure)):
                FailureView(failure: failure)
            }
        }
    }
}

/// One-time, unobtrusive offer to support the author (see `DonationPrompt`).
private struct DonationOfferView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // The heart is centered next to the message; the close button sits in the corner.
        HStack(spacing: 12) {
            Image(systemName: "heart.fill")
                .font(.title)
                .foregroundStyle(.pink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("You have been using CardGate for a while. If it helps you, you can support the author.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Support on Ko-fi") { model.finishDonationOffer(openingPage: true) }
                    .buttonStyle(.link)
            }
        }
        .padding(.trailing, 22)
        .font(.callout)
        .padding(12)
        .frame(maxWidth: 380)
        .overlay(alignment: .topTrailing) {
            Button {
                model.finishDonationOffer(openingPage: false)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close and do not show again")
            .accessibilityLabel(Text("Close and do not show again"))
            .padding(12)
        }
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
