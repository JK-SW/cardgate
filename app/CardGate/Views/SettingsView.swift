import CardGateKit
import SwiftUI

/// CardGate → Settings: options of the app itself (each connection has its own settings).
struct SettingsView: View {
    @Bindable var updater: Updater

    private static let updatesExplanation: LocalizedStringKey =
        "Once a day CardGate asks GitHub whether a new version is available. Nothing about you is sent."

    private static let keepConnectionExplanation: LocalizedStringKey = """
        After a short network outage CardGate tries to connect again without you having to enter the PIN.
        """

    @AppStorage(SessionOptions.Key.keepConnection) private var keepConnection = SessionOptions.onByDefault
    @AppStorage(SessionOptions.Key.preventSleep) private var preventSleep = SessionOptions.onByDefault
    @AppStorage(SessionOptions.Key.confirmDisconnect) private var confirmDisconnect = SessionOptions.onByDefault

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $keepConnection) {
                    Text("Keep the connection alive and restore it after an outage")
                    Text(Self.keepConnectionExplanation)
                }
                .accessibilityIdentifier("settings.keepConnection")
                Toggle(isOn: $preventSleep) {
                    Text("Keep the Mac awake while connected")
                    Text("The display may still turn off; closing the lid still puts the Mac to sleep.")
                }
                .accessibilityIdentifier("settings.preventSleep")
                Toggle(isOn: $confirmDisconnect) {
                    Text("Ask before disconnecting")
                    Text("When you close the remote desktop window or press ⌘Q in it.")
                }
                .accessibilityIdentifier("settings.confirmDisconnect")
            } header: {
                Text("Connection")
            } footer: {
                Text("Changes apply to the next connection.")
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $updater.automaticallyChecksForUpdates) {
                    Text("Check for updates automatically")
                    Text(updater.isAvailable ? Self.updatesExplanation : "Updates are not available in this build.")
                }
                .disabled(!updater.isAvailable)
                .accessibilityIdentifier("settings.automaticUpdates")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
