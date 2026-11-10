import SwiftUI

/// Keyboard shortcuts of the remote desktop window (FreeRDP client hotkeys, see
/// `FreeRDPClientConfig`): left Control + left Option + left Shift together with a key.
struct KeyboardShortcutsView: View {
    private struct Shortcut: Identifiable {
        let key: String
        let action: LocalizedStringKey
        var id: String { key }
    }

    private let shortcuts = [
        Shortcut(key: "↩", action: "Switch between window and full screen"),
        Shortcut(key: "D", action: "Disconnect"),
        Shortcut(key: "M", action: "Minimize the window"),
        Shortcut(key: "G", action: "Capture keyboard and mouse (system shortcuts go to Windows)"),
        Shortcut(key: "R", action: "Allow or prevent resizing the window"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts")
                .font(.title2.weight(.semibold))
            Text("In the remote desktop window hold the left ⌃ Control, ⌥ Option and ⇧ Shift keys and press:")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 10) {
                ForEach(shortcuts) { shortcut in
                    GridRow {
                        Text("⌃⌥⇧ \(shortcut.key)")
                            .font(.system(.body, design: .monospaced).weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                        Text(shortcut.action)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Text("All other key combinations are sent to Windows.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 460)
    }
}
