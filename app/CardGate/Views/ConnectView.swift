import CardGateKit
import SwiftUI

/// Main window: the selected connection, its status and the Connect button.
struct ConnectView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            if let profile = model.selectedProfile {
                VStack(spacing: 24) {
                    Spacer(minLength: 0)
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
                    SessionStatusView(phase: model.session.phase)
                        .frame(minHeight: 44)
                    connectButton
                    Spacer(minLength: 0)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            MiddlewareStatusView()
                .padding(.horizontal)
                .padding(.vertical, 10)
        }
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
                Text("Connect").frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.extraLarge)
            .keyboardShortcut(.defaultAction)
            .disabled(model.middleware == nil)
        }
    }
}

/// Human readable connection progress and errors with advice.
struct SessionStatusView: View {
    let phase: SessionPhase?

    var body: some View {
        switch phase {
        case nil, .ended(.closedByUser):
            Text("Insert your card and click Connect.")
                .foregroundStyle(.secondary)
        case .starting:
            progress("Starting…")
        case .authenticatingGateway:
            progress("Signing in to the gateway – enter the PIN of your card.")
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
        }
        .frame(maxWidth: 380)
    }

    private var title: LocalizedStringKey {
        switch failure {
        case .noCertificate: "No certificate found on the card"
        case .wrongPIN: "Wrong PIN"
        case .cardLocked: "The card is locked"
        case .gatewayUnreachable: "The gateway cannot be reached"
        case .gatewayDenied: "The gateway refused the sign-in"
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
        case .computerUnreachable:
            "The computer may be turned off or the address is wrong. Contact your IT department if it persists."
        case .other(let code):
            "Details are in the connection log (\(code))."
        }
    }
}

/// Footer showing whether smart card middleware is installed.
struct MiddlewareStatusView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack {
            if let middleware = model.middleware {
                Label {
                    Text("Smart card software: \(middleware.name)")
                } icon: {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)
                }
            } else {
                Label {
                    Text("No smart card software found")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                Spacer()
                if let url = PKCS11ModuleLocator.knownMiddleware.first?.downloadURL {
                    Link("Download ProID+", destination: url)
                }
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}
