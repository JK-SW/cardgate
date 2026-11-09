import AppKit
import SwiftUI

/// Log of the last connection, for troubleshooting with the IT department.
struct LogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let lines = model.session.log
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines.indices, id: \.self) { index in
                        Text(lines[index])
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(of: lines[index]))
                            .id(index)
                    }
                }
                .textSelection(.enabled)
                .padding(8)
            }
            .onChange(of: lines.count) { _, count in
                if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
            }
        }
        .overlay {
            if lines.isEmpty {
                ContentUnavailableView(
                    "No connection yet", systemImage: "text.alignleft",
                    description: Text("The log of the last connection appears here."))
            }
        }
        .toolbar {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
            } label: {
                Label("Copy Log", systemImage: "doc.on.doc")
            }
            .help("Copy the log to send it to your IT department")
            .disabled(lines.isEmpty)
        }
    }

    private func color(of line: String) -> Color {
        if line.contains("[ERROR]") { return .red }
        if line.contains("[WARN]") { return .orange }
        return .primary
    }
}
