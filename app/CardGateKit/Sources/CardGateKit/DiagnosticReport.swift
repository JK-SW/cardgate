public import Foundation

/// Anonymous diagnostic information for the saved log (`LogArchive`): versions, the Mac, its
/// displays, the card's software and the connection's settings – never names, addresses, the
/// card's holder or certificates. Plain text in English (for whoever helps), one value per line.
public struct DiagnosticReport: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public var title: String
        public var items: [(String, String)]

        public init(_ title: String, _ items: [(String, String)]) {
            self.title = title
            self.items = items
        }

        public static func == (lhs: Section, rhs: Section) -> Bool {
            lhs.title == rhs.title && lhs.items.map(\.0) == rhs.items.map(\.0)
                && lhs.items.map(\.1) == rhs.items.map(\.1)
        }
    }

    public var sections: [Section]

    public init(sections: [Section]) {
        self.sections = sections
    }

    /// "[Mac]\nmacOS: 26.2\n…", sections separated by an empty line.
    public var text: String {
        sections.map { section in
            (["[\(section.title)]"] + section.items.map { "\($0.0): \(Self.oneLine($0.1))" }).joined(separator: "\n")
        }
        .joined(separator: "\n\n") + "\n"
    }

    static func oneLine(_ value: String) -> String {
        value.components(separatedBy: .newlines).joined(separator: " ")
    }

    /// A path without the user's name: the home folder becomes "~".
    public static func anonymizedPath(_ path: String, home: String = NSHomeDirectory()) -> String {
        let home = home.hasSuffix("/") ? String(home.dropLast()) : home
        guard !home.isEmpty, path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }

    public static func yesNo(_ value: Bool) -> String { value ? "yes" : "no" }

    /// "2026-11-26 15:39:04 UTC (local time UTC+01:00)": to compare with the log's local times and
    /// the domain's clock.
    public static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        let utc = ISO8601DateFormatter()
        utc.formatOptions = [.withFullDate, .withSpaceBetweenDateAndTime, .withTime, .withColonSeparatorInTime]
        utc.timeZone = TimeZone(identifier: "UTC")
        let seconds = timeZone.secondsFromGMT(for: date)
        let offset = String(
            format: "%@%02d:%02d", seconds < 0 ? "-" : "+", abs(seconds) / 3600, abs(seconds) % 3600 / 60)
        return "\(utc.string(from: date)) UTC (local time UTC\(offset))"
    }
}

/// The saved log: a ZIP archive with the important messages, the whole log and the diagnostic
/// information (`DiagnosticReport`).
public enum LogArchive {
    public static let importantName = "important.txt"
    public static let logName = "connection.log"
    public static let diagnosticsName = "diagnostics.txt"

    /// "CardGate-log-2026-11-26-1639.zip"
    public static func name(at date: Date) -> String {
        SessionLogFiles.exportName(at: date).replacingOccurrences(of: ".log", with: ".zip")
    }

    /// Writes the files into a ZIP archive (`ditto`, the Finder's format) and returns its contents.
    /// - Parameter folder: the folder inside the archive.
    public static func make(folder: String, files: [(name: String, data: Data)]) throws -> Data {
        let fileManager = FileManager.default
        let work = fileManager.temporaryDirectory.appending(path: "CardGate-\(UUID().uuidString)")
        defer { try? fileManager.removeItem(at: work) }
        let content = work.appending(path: folder)
        try fileManager.createDirectory(at: content, withIntermediateDirectories: true)
        for file in files {
            try file.data.write(to: content.appending(path: file.name))
        }
        let archive = work.appending(path: "archive.zip")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--norsrc", "--keepParent", content.path, archive.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
        return try Data(contentsOf: archive)
    }
}
