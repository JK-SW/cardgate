import CardGateKit
import SwiftUI

/// The saved connections, the card and the commands to add a connection.
struct ConnectionSidebar: View {
    @Environment(AppModel.self) private var model

    /// Opens at the minimum width: a long name or address is shortened, the user can widen the
    /// sidebar up to the maximum.
    static let minimumWidth: CGFloat = 230
    static let maximumWidth: CGFloat = 380

    var body: some View {
        List(selection: selection) {
            Section("Connections") {
                ForEach(model.profiles) { profile in
                    ConnectionRow(profile: profile)
                        .tag(profile.id)
                }
            }
        }
        // While a connection starts or runs, the selected one must not change.
        .disabled(model.isBusy)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                CardStatusTile()
                HStack {
                    // A new or imported connection would become the selected one while another runs.
                    Button {
                        model.beginNewProfile()
                    } label: {
                        Label("New Connection…", systemImage: "plus")
                    }
                    .accessibilityIdentifier("sidebar.new")
                    Spacer()
                    Button {
                        model.isImportingRDP = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Import .rdp File…")
                    .accessibilityLabel(Text("Import .rdp File…"))
                    .accessibilityIdentifier("sidebar.import")
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 6)
                .disabled(model.isBusy)
            }
            .padding(10)
        }
    }

    private var selection: Binding<UUID?> {
        Binding(get: { model.selectedProfile?.id }, set: { if let id = $0 { model.select(id) } })
    }
}

private struct ConnectionRow: View {
    @Environment(AppModel.self) private var model
    let profile: ConnectionProfile

    var body: some View {
        HStack(spacing: 6) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(profile.name)
                        .lineLimit(1)
                    Text(profile.computer.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } icon: {
                Image(systemName: "desktopcomputer")
            }
            .labelStyle(CenteredIconLabelStyle())
            // The texts get the room first, not the spacer before the button.
            .layoutPriority(1)
            Spacer(minLength: 4)
            Button {
                model.beginEditing(profile)
            } label: {
                Image(systemName: "slider.horizontal.3")
            }
            .buttonStyle(.borderless)
            .help("Edit Connection")
            .accessibilityLabel(Text("Edit Connection"))
            .accessibilityIdentifier("connection.edit")
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button("Edit Connection") { model.beginEditing(profile) }
                .disabled(model.isBusy)
        }
    }
}

/// The icon centered on both lines of the row, level with the edit button (a plain label aligns
/// it with the first line).
private struct CenteredIconLabelStyle: LabelStyle {
    /// Increased in the selected row of the active window: the icon turns white like the texts.
    @Environment(\.backgroundProminence) private var prominence

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 8) {
            configuration.icon
                // The accent color of the sidebar's own labels.
                .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(.tint))
                .frame(width: 20)
            configuration.title
        }
    }
}
