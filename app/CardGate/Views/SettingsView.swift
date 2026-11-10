import SwiftUI

/// CardGate → Settings: options of the app itself (each connection has its own settings).
struct SettingsView: View {
    @Bindable var updater: Updater

    private static let updatesExplanation: LocalizedStringKey =
        "Once a day CardGate asks GitHub whether a new version is available. Nothing about you is sent."

    var body: some View {
        Form {
            Section {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                    .disabled(!updater.isAvailable)
            } footer: {
                Text(updater.isAvailable ? Self.updatesExplanation : "Updates are not available in this build.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
