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
                }
                ReadinessView()
                SessionStatusView(phase: model.session.phase)
                connectButton
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
                    .disabled(model.session.isRunning)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if let profile = model.selectedProfile { model.beginEditing(profile) }
                } label: {
                    Label("Edit Connection", systemImage: "slider.horizontal.3")
                }
                .help("Edit Connection")
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
            }
        }
    }

    @ViewBuilder private var connectButton: some View {
        if model.session.isRunning {
            Button(role: .destructive) {
                model.session.stop()
            } label: {
                Text("Disconnect").frame(minWidth: 200)
            }
            .controlSize(.extraLarge)
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

    var body: some View {
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
            "The computer may be turned off or the address is wrong. Contact your IT department if it persists."
        case .other(let code):
            "Details are in the connection log (\(code))."
        }
    }
}
