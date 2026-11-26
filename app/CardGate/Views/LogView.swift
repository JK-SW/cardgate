import AppKit
import CardGateKit
import SwiftUI
import UniformTypeIdentifiers

/// Log of the last connection, for troubleshooting with the IT department. By default it shows the
/// important events in words; Details shows the client's own lines (harmless warnings grayed out).
/// Copy Log and Save Log always take the client's whole log as it was written.
struct LogView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(Self.importantOnlyKey) private var importantOnly = true

    /// Remembered, so whoever turned it off for troubleshooting keeps the details.
    static let importantOnlyKey = "LogImportantMessagesOnly"

    var body: some View {
        let hasLog = model.session.hasLog
        let entries = model.session.eventEntries
        let logFile = model.session.logFileURL
        Group {
            if importantOnly {
                EventList(entries: entries)
            } else {
                LineList()
            }
        }
        .overlay {
            if !hasLog, entries.isEmpty {
                ContentUnavailableView(
                    "No connection yet", systemImage: "text.alignleft",
                    description: Text("The log of the last connection appears here."))
            } else if !hasLog, !importantOnly {
                ContentUnavailableView(
                    "The client has not written anything yet", systemImage: "text.alignleft",
                    description: Text("Its lines appear here once it starts."))
            }
        }
        .toolbar {
            Picker("Show", selection: $importantOnly) {
                Text("Important").tag(true)
                Text("Details").tag(false)
            }
            .pickerStyle(.segmented)
            .help("Important: the steps and problems of the connection in words. Details: every line of the log.")
            .accessibilityIdentifier("log.view")
            Button(action: copyLog) {
                Label("Copy Log", systemImage: "doc.on.doc")
            }
            .help("Copy the whole log with every detail, to send it to your IT department")
            .disabled(!hasLog && logFile == nil)
            Button(action: saveLog) {
                Label("Save Log…", systemImage: "square.and.arrow.down")
            }
            .help("Save the whole log with every detail to a file")
            .disabled(logFile == nil)
        }
    }
}

extension LogView {
    /// The whole log as the client wrote it (with the command line), from its file; the lines kept
    /// in memory are only the most recent ones.
    private func copyLog() {
        let session = model.session
        let file = session.logFileURL
        let lines = session.log.texts
        Task {
            // A long log is read off the main thread.
            let text = await Task.detached { file.flatMap { try? String(contentsOf: $0, encoding: .utf8) } }.value
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text ?? lines.joined(separator: "\n"), forType: .string)
        }
    }

    /// Saves a copy of the shown connection's log file.
    private func saveLog() {
        guard let source = model.session.logFileURL else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = SessionLogFiles.exportName(at: .now)
        panel.allowedContentTypes = [.log]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }
        do {
            // Read whole, then written atomically: an existing file is replaced only by a complete copy
            // (also on a USB stick or a network share, and when it is the log file itself).
            try Data(contentsOf: source).write(to: target, options: .atomic)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

/// Follows the end of a list as lines are added.
private struct FollowingList<Item: Identifiable, Row: View>: View where Item.ID == Int {
    let items: [Item]
    /// Long lines of the client scroll sideways; sentences wrap to the window's width.
    var axes: Axis.Set = [.vertical, .horizontal]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(axes) {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(items) { row($0) }
                }
                .textSelection(.enabled)
                .padding(8)
            }
            // By the number of the last line: it changes with every new line, also once old lines
            // are dropped and the count stays the same.
            .onChange(of: items.last?.id, initial: true) { _, last in
                if let last { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }
}

/// The client's lines; known harmless warnings and errors are grayed out.
/// Only this view follows every new line of the client.
private struct LineList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        _ = model.session.logRevision
        return FollowingList(items: model.session.log.lines) { line in
            Text(verbatim: line.text)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Self.style(of: line.kind))
        }
    }

    static func style(of kind: LogLineKind) -> Color {
        switch kind {
        case .normal: .primary
        case .harmless: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}

/// The important events: time, an icon and a sentence.
private struct EventList: View {
    let entries: [ConnectionLog.Entry]

    var body: some View {
        FollowingList(items: entries, axes: .vertical) { entry in
            let severity = entry.event.severity
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: Self.symbol(of: severity))
                    .foregroundStyle(Self.color(of: severity))
                    .accessibilityLabel(Self.label(of: severity))
                Text(verbatim: entry.time)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                message(of: entry.event)
                    .foregroundStyle(severity == .info ? .primary : Self.color(of: severity))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 1)
        }
    }

    @ViewBuilder
    private func message(of event: ConnectionLogEvent) -> some View {
        if case .unknown(let text, _) = event {
            Text(verbatim: text).font(.system(.caption, design: .monospaced))
        } else if let message = event.message {
            Text(message)
        }
    }

    static func symbol(of severity: ConnectionLogEvent.Severity) -> String {
        switch severity {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    static func color(of severity: ConnectionLogEvent.Severity) -> Color {
        switch severity {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }

    static func label(of severity: ConnectionLogEvent.Severity) -> Text {
        switch severity {
        case .info: Text("Information")
        case .warning: Text("Warning")
        case .error: Text("Error")
        }
    }
}

extension ConnectionLogEvent {
    /// The sentence of the important messages view; `nil` for a line of the client (`unknown`).
    fileprivate var message: LocalizedStringKey? {
        switch self {
        case .connecting: "Connecting…"
        case .signingInToGateway: "Signing in to the gateway with the card…"
        case .gatewayAccepted: "The gateway accepted the card."
        case .security(.nla): "The connection to the computer is secured with NLA."
        case .security(.tls): "The connection to the computer is secured with TLS."
        case .security(.rdp):
            "The computer uses RDP Security with the older RC4 encryption. Windows asks for your sign-in details again."
        case .desktopShown: "The remote desktop is open."
        case .signedIn: "Signed in to Windows."
        case .changedCertificateTrusted:
            "The computer's changed certificate was trusted (confirmed by its fingerprint)."
        case .renewedCertificateVerified: "The computer's renewed certificate was verified by Kerberos and saved."
        case .connectionInterrupted: "The connection was interrupted. Reconnecting…"
        case .reconnecting(let attempt, let total): "Reconnecting (attempt \(attempt) of \(total))…"
        case .reconnected: "The connection was restored."
        case .scaleChanged(let percent?):
            "The scale of the remote desktop was changed to \((Double(percent) / 100).formatted(.percent))."
        case .scaleChanged(nil): "The remote desktop uses the scale of each display again."
        case .ended(.closedByUser): "Disconnected."
        case .ended(.failed(.other(let code))): "The connection failed (\(code))"
        case .ended(.failed(let failure)): failure.title
        case .unknown: nil
        }
    }
}
