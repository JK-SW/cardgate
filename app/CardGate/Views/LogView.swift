import AppKit
import CardGateKit
import SwiftUI
import UniformTypeIdentifiers

/// Log of the last connection, for troubleshooting with the IT department. By default it shows the
/// important events in words; Details shows the client's own lines (harmless warnings grayed out).
/// Copy Log copies what is shown; Save Log saves a ZIP archive with the important messages, the
/// client's whole log and anonymous diagnostic information (`LogArchive`), without the names of the
/// computer, the gateway and the account (`LogAnonymizer`).
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
            .help("Copy what the window shows: the important messages, or every line of the log")
            .disabled(importantOnly ? entries.isEmpty : !hasLog && logFile == nil)
            Button(action: saveLog) {
                Label("Save Log…", systemImage: "square.and.arrow.down")
            }
            .help(
                """
                Save a ZIP archive with the important messages, the whole log and diagnostic information, \
                without the names of the computer, the gateway and your account, to send it to your IT department
                """
            )
            .disabled(entries.isEmpty && !hasLog && logFile == nil)
        }
    }
}

extension LogView {
    /// Copies what the window shows: the important messages as text, or the whole log as the client
    /// wrote it (with the command line, from its file; the lines kept in memory are only the most
    /// recent ones).
    private func copyLog() {
        let session = model.session
        if importantOnly {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(Self.importantText(session.eventEntries), forType: .string)
            return
        }
        let file = session.logFileURL
        let lines = session.log.texts
        Task {
            // Bytes that are not UTF-8 (e.g. a device name) are replaced, the rest is kept: on purpose
            // not the failable initializer, which would drop the whole log.
            // swiftlint:disable:next optional_data_string_conversion
            let text = String(decoding: await Self.wholeLog(file: file, lines: lines), as: UTF8.self)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    /// Saves a ZIP archive with the important messages, the whole log and the diagnostic information.
    private func saveLog() {
        let session = model.session
        let now = Date.now
        let panel = NSSavePanel()
        panel.nameFieldStringValue = LogArchive.name(at: now)
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let target = panel.url else { return }
        let anonymizer = model.logAnonymizer
        let important = Self.importantText(session.eventEntries)
        let diagnostics = model.diagnosticReport(at: now).text
        let file = session.logFileURL
        let lines = session.log.texts
        let folder = String(LogArchive.name(at: now).dropLast(".zip".count))
        Task {
            let log = await Self.wholeLog(file: file, lines: lines)
            let result = await Task.detached {
                Result {
                    // Without the names of the computer, the gateway and the account (`LogAnonymizer`); bytes
                    // that are not UTF-8 are replaced.
                    // swiftlint:disable:next optional_data_string_conversion
                    let text = String(decoding: log, as: UTF8.self)
                    // The same for both files: also the names the log's command line gives.
                    let names = anonymizer.adding(commandLine: text)
                    let log = Data(names.anonymize(text).utf8)
                    let important = names.anonymize(important)
                    let archive = try LogArchive.make(
                        folder: folder,
                        files: [
                            (LogArchive.importantName, Data(important.utf8)), (LogArchive.logName, log),
                            (LogArchive.diagnosticsName, Data(diagnostics.utf8)),
                        ])
                    // Written atomically: an existing file is replaced only by a complete archive.
                    try archive.write(to: target, options: .atomic)
                }
            }.value
            if case .failure(let error) = result { NSAlert(error: error).runModal() }
        }
    }

    /// The whole log from its file as written (read off the main thread), or the lines in memory.
    private static func wholeLog(file: URL?, lines: [String]) async -> Data {
        let data = await Task.detached { file.flatMap { try? Data(contentsOf: $0) } }.value
        return data ?? Data(lines.joined(separator: "\n").utf8)
    }

    /// "16:38:29  ⚠ The connection was interrupted. Reconnecting…", one message per line, as shown.
    static func importantText(_ entries: [ConnectionLog.Entry]) -> String {
        entries.map { entry in
            let mark =
                switch entry.event.severity {
                case .info: ""
                case .warning: "⚠ "
                case .error: "✖ "
                }
            let text: String =
                if case .unknown(let text, _) = entry.event { text } else { entry.event.message ?? "" }
            return "\(entry.time)  \(mark)\(text)"
        }
        .joined(separator: "\n") + "\n"
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
    var message: String? {
        switch self {
        case .connecting: String(localized: "Connecting…")
        case .signingInToGateway: String(localized: "Signing in to the gateway with the card…")
        case .gatewayAccepted: String(localized: "The gateway accepted the card.")
        case .security(.nla): String(localized: "The connection to the computer is secured with NLA.")
        case .security(.tls): String(localized: "The connection to the computer is secured with TLS.")
        case .security(.rdp):
            String(
                localized: """
                    The computer uses RDP Security with the older RC4 encryption. Windows asks for your sign-in \
                    details again.
                    """)
        case .desktopShown: String(localized: "The remote desktop is open.")
        case .signedIn: String(localized: "Signed in to Windows.")
        case .changedCertificateTrusted:
            String(localized: "The computer's changed certificate was trusted (confirmed by its fingerprint).")
        case .renewedCertificateVerified:
            String(localized: "The computer's renewed certificate was verified by Kerberos and saved.")
        case .connectionInterrupted: String(localized: "The connection was interrupted. Reconnecting…")
        case .gatewaySessionExpired:
            String(localized: "The gateway ended the connection when its time limit ran out. Reconnecting…")
        case .soundFailed: String(localized: "Playing sound failed.")
        case .reconnecting(let attempt, let total): String(localized: "Reconnecting (attempt \(attempt) of \(total))…")
        case .reconnected: String(localized: "The connection was restored.")
        case .reconnectFailed(let failure): String(localized: "A reconnection attempt failed: \(failure.title)")
        case .cardRemoved: String(localized: "The card was removed from the reader.")
        case .cardInserted: String(localized: "The card is back in the reader.")
        case .scaleChanged(let percent?):
            String(
                localized:
                    "The scale of the remote desktop was changed to \((Double(percent) / 100).formatted(.percent)).")
        case .scaleChanged(nil): String(localized: "The remote desktop uses the scale of each display again.")
        case .ended(.closedByUser): String(localized: "Disconnected.")
        case .ended(.failed(.other(let code))): String(localized: "The connection failed (\(code))")
        case .ended(.failed(let failure)): failure.title
        case .unknown: nil
        }
    }
}
