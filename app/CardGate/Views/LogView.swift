import AppKit
import SwiftUI

/// Log of the last connection, for troubleshooting with the IT department.
struct LogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let lines = model.session.log.lines
        ScrollViewReader { proxy in
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(color(of: line.text))
                    }
                }
                .textSelection(.enabled)
                .padding(8)
            }
            // By the number of the last line: it changes with every new line, also once old lines
            // are dropped and the count stays the same.
            .onChange(of: lines.last?.id) { _, last in
                if let last { proxy.scrollTo(last, anchor: .bottom) }
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
                NSPasteboard.general.setString(model.session.log.texts.joined(separator: "\n"), forType: .string)
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
