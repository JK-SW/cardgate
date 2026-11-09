import SwiftUI

/// First start: no connection is set up yet.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            AppSymbol()
                .font(.system(size: 64))
            VStack(spacing: 8) {
                Text("Welcome to CardGate")
                    .font(.largeTitle.weight(.semibold))
                Text("Connect to your work computer with your smart card.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(spacing: 10) {
                Button {
                    model.beginNewProfile()
                } label: {
                    Text("Set Up Connection")
                        .frame(minWidth: 220)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)

                Button("Import .rdp File…") { model.isImportingRDP = true }
                    .buttonStyle(.link)
            }
            Spacer()
            MiddlewareStatusView()
                .padding(.bottom)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The app's symbol: a desktop computer with a card.
struct AppSymbol: View {
    var body: some View {
        Image(systemName: "lock.display")
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }
}
