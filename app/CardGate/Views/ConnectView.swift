import CardGateKit
import SwiftUI

/// Main window: the selected connection, readiness of the card, status and the Connect button.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 20) {
            if let profile = model.selectedProfile {
                AppSymbol()
                    .font(.system(size: 52))
                VStack(spacing: 6) {
                    Text(profile.name)
                        .font(.title.weight(.semibold))
                    Text(profile.computer.description)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                    if let gateway = profile.gateway {
                        Label {
                            Text("via \(gateway.description)")
                        } icon: {
                            Image(systemName: "network.badge.shield.half.filled")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                    GatewayStatusView()
                }
                ReadinessView()
                SessionStatusView(phase: model.session.phase, stopping: model.session.isStopping)
                connectButton
                if model.showsDonationOffer && !model.session.isRunning {
                    DonationOfferView()
                        .transition(.opacity)
                }
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 32)
        .frame(maxWidth: .infinity)
        .toolbar {
            if model.profiles.count > 1 {
                ToolbarItem(placement: .navigation) {
                    Picker("Connection", selection: $model.selectedID) {
                        ForEach(model.profiles) { profile in
                            Text(profile.name).tag(Optional(profile.id))
                        }
                    }
                    // A long name is shortened; otherwise the buttons would move to an overflow menu.
                    .frame(maxWidth: 220)
                    .disabled(model.session.isRunning)
                }
                // Keeps the buttons on the right, where the title's space used to put them.
                if #available(macOS 26, *) {
                    ToolbarSpacer(.flexible)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if let profile = model.selectedProfile { model.beginEditing(profile) }
                } label: {
                    Label("Edit Connection", systemImage: "slider.horizontal.3")
                }
                .help("Edit Connection")
                .accessibilityIdentifier("toolbar.edit")
                .disabled(model.session.isRunning)

                Menu {
                    Button("New Connection…") { model.beginNewProfile() }
                    Button("Import .rdp File…") { model.isImportingRDP = true }
                    Divider()
                    Button("Keyboard Shortcuts") { openWindow(id: WindowID.shortcuts) }
                    Button("Connection Log") { openWindow(id: WindowID.log) }
                } label: {
                    Label("More", systemImage: "plus")
                }
                .help("Add a connection or show the log")
                .accessibilityIdentifier("toolbar.more")
            }
        }
        // With the connection picker there is no room for the window title (the name is shown below).
        .toolbar(removing: model.profiles.count > 1 ? .title : nil)
    }

    @ViewBuilder private var connectButton: some View {
        if model.session.isRunning {
            // Until the desktop is shown there is nothing to disconnect: the attempt is cancelled.
            let connected = model.session.phase == .connected
            Button(role: .destructive) {
                model.session.stop()
            } label: {
                Text(connected ? "Disconnect" : "Cancel").frame(minWidth: 200)
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
                .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .disabled(!model.isReadyToConnect)
            .accessibilityIdentifier("connect")
        }
    }
}

/// A problem with the gateway found while idle (nothing is shown while it is fine).
private struct GatewayStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Not while connecting, nor next to a failure that already says the gateway is unreachable;
        // after an interrupted connection it shows whether the network is back.
        if !model.session.isRunning, model.session.phase != .ended(.failed(.gatewayUnreachable)) {
            if model.gatewayStatus == .unreachable {
                Label(
                    "The gateway cannot be reached. Check your internet connection and the gateway address.",
                    systemImage: "wifi.exclamationmark"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            }
        }
    }
}

/// Whether the smart card software is installed and a card with a sign-in certificate is inserted.
struct ReadinessView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.moduleUntrusted {
                Label("The smart card module is not signed and was not loaded.", systemImage: "xmark.shield.fill")
                    .foregroundStyle(.red)
            } else if model.middleware == nil {
                VStack(spacing: 6) {
                    Label("No smart card software found", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    if let url = PKCS11ModuleLocator.knownMiddleware.first?.downloadURL {
                        Link("Download ProID+", destination: url)
                    }
                }
            } else if model.cardNeedsReinsert {
                VStack(spacing: 4) {
                    Label("The card is not available to sign in.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Remove the card or token and insert it again.")
                        .foregroundStyle(.secondary)
                }
            } else if let certificate = model.signInCertificate {
                VStack(spacing: 3) {
                    HStack(spacing: 8) {
                        Label {
                            Text("Card ready: \(certificate.holderName)")
                        } icon: {
                            Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                        }
                        if model.cards.isChecking {
                            ProgressView().controlSize(.small)
                                .help("Checking the card…")
                        }
                    }
                    if let notAfter = certificate.notAfter {
                        Text("Certificate valid until \(notAfter.formatted(date: .long, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let days = CardCertificate.expiryWarning(for: model.cards.certificates, at: Date()) {
                        ExpiryWarningView(days: days)
                            .padding(.top, 6)
                    }
                }
            } else if CardCertificate.allLogonCertificatesExpired(model.cards.certificates, at: Date()) {
                VStack(spacing: 4) {
                    Label(
                        "The sign-in certificate on the card has expired.",
                        systemImage: "calendar.badge.exclamationmark"
                    )
                    .foregroundStyle(.orange)
                    Text("Contact your IT department to renew it.")
                        .foregroundStyle(.secondary)
                }
            } else if model.cards.isReadingCard {
                Label {
                    Text("Reading the card…")
                } icon: {
                    ProgressView().controlSize(.small)
                }
                .foregroundStyle(.secondary)
            } else if model.cards.certificates.isEmpty {
                Label("Insert your card or token.", systemImage: "creditcard")
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    "The inserted card has no certificate for signing in.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            }
        }
        .font(.callout)
        .multilineTextAlignment(.center)
        .animation(.default, value: model.signInCertificate)
    }
}

/// Notice that the newest sign-in certificate expires soon.
private struct ExpiryWarningView: View {
    let days: Int

    var body: some View {
        VStack(spacing: 2) {
            Label {
                if days == 0 {
                    Text("The sign-in certificate expires today.")
                } else {
                    Text("The sign-in certificate expires in \(days) days.")
                }
            } icon: {
                Image(systemName: "calendar.badge.exclamationmark")
            }
            .foregroundStyle(.orange)
            .fontWeight(.medium)
            Text("Ask your IT department to renew it in time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Human readable connection progress and errors with advice.
struct SessionStatusView: View {
    let phase: SessionPhase?
    /// Cancel or Disconnect was chosen and the client is quitting.
    var stopping = false

    var body: some View {
        if stopping {
            progress(phase == .connected ? "Disconnecting…" : "Cancelling…")
        } else {
            phaseView
        }
    }

    @ViewBuilder private var phaseView: some View {
        switch phase {
        case nil, .ended(.closedByUser):
            EmptyView()
        case .starting:
            progress("Connecting…")
        case .waitingForPIN:
            progress("Enter the PIN of your card in the dialog.")
        case .authenticatingGateway:
            progress("Signing in to the gateway…")
        case .connectingComputer:
            progress("Connecting to the computer…")
        case .connected:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .ended(.failed(let failure)):
            FailureView(failure: failure)
        }
    }

    private func progress(_ text: LocalizedStringKey) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
        }
        .foregroundStyle(.secondary)
    }
}

private struct FailureView: View {
    let failure: SessionFailure

    var body: some View {
        VStack(spacing: 4) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.headline)
            Text(advice)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: 420)
    }

    private var title: LocalizedStringKey {
        switch failure {
        case .noCertificate: "No certificate found on the card"
        case .wrongPIN: "Wrong PIN"
        case .cardLocked: "The card is locked"
        case .gatewayUnreachable: "The gateway cannot be reached"
        case .gatewayDenied: "The gateway refused the sign-in"
        case .untrustedCertificate: "The gateway's certificate is not trusted"
        case .multipleCertificates: "The card has several sign-in certificates"
        case .pinTimedOut: "The PIN was not entered in time"
        case .computerUnreachable: "The computer cannot be reached"
        case .securityRefused: "The computer requires a different connection security"
        case .connectionLost: "The connection was interrupted"
        case .sessionTakenOver: "Another connection took over the session"
        case .idleTimeout: "Disconnected after a period of inactivity"
        case .disconnectedByServer: "The computer ended the connection"
        case .other: "The connection failed"
        }
    }

    private var advice: LocalizedStringKey {
        switch failure {
        case .noCertificate:
            "Remove the card or token, insert it again and try once more."
        case .wrongPIN:
            "The PIN was not accepted. Be careful: after several wrong attempts the card gets locked."
        case .cardLocked:
            "Too many wrong PINs were entered. Unlock the card with the PUK or contact your IT department."
        case .gatewayUnreachable:
            "Check your internet connection and the gateway address in the connection settings."
        case .gatewayDenied:
            "Your card is not allowed to use this gateway. Contact your IT department."
        case .untrustedCertificate:
            """
            The connection was stopped for your safety. Check the gateway address; if it is correct, \
            contact your IT department.
            """
        case .multipleCertificates:
            """
            CardGate cannot choose between them yet. Use a card with one sign-in certificate or contact \
            your IT department.
            """
        case .pinTimedOut:
            "The gateway does not wait long for the PIN. Click Connect and enter the PIN right away."
        case .computerUnreachable:
            """
            The gateway could not reach it. Check the computer's name in the connection settings for a typo \
            and whether the computer is turned on. Contact your IT department if it persists.
            """
        case .securityRefused:
            """
            The computer does not accept the connection security CardGate uses (it requires TLS or NLA). \
            Contact your IT department.
            """
        case .connectionLost:
            "Check your internet connection and connect again."
        case .sessionTakenOver:
            "Someone signed in to the computer, or you connected to it from another device."
        case .idleTimeout:
            "The computer ends idle connections. Connect again to continue."
        case .disconnectedByServer:
            """
            An administrator or the computer itself disconnected you (for example before a restart). \
            Try again later or contact your IT department.
            """
        case .other(let code):
            "Details are in the connection log (\(code))."
        }
    }
}

/// One-time, unobtrusive offer to support the author (see `DonationPrompt`).
private struct DonationOfferView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.fill")
                .foregroundStyle(.pink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text("You have been using CardGate for a while. If it helps you, you can support the author.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Support on Ko-fi") { model.finishDonationOffer(openingPage: true) }
                    .buttonStyle(.link)
            }
            Button {
                model.finishDonationOffer(openingPage: false)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Close and do not show again")
            .accessibilityLabel(Text("Close and do not show again"))
        }
        .font(.callout)
        .padding(12)
        .frame(maxWidth: 380)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
}
