public import Foundation

/// Log files of the last few connections, kept for support (they never contain the PIN).
///
/// The newest is `last-session.log`, older ones `last-session.1.log` … `last-session.<keep-1>.log`,
/// so a failed attempt is still there after the user tried again.
public struct SessionLogFiles: Sendable {
    public let directory: URL
    public let keep: Int

    public init(directory: URL, keep: Int = 5) {
        self.directory = directory
        self.keep = max(keep, 1)
    }

    public static var standard: SessionLogFiles {
        SessionLogFiles(
            directory: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/CardGate"))
    }

    /// Log of the most recent connection.
    public var latest: URL { url(index: 0) }

    /// `index` 0 is the newest log.
    public func url(index: Int) -> URL {
        directory.appending(path: index == 0 ? "last-session.log" : "last-session.\(index).log")
    }

    /// Shifts the existing logs by one (dropping the oldest) and creates an empty newest log.
    public func startNew() throws -> FileHandle {
        let files = FileManager.default
        try files.createDirectory(at: directory, withIntermediateDirectories: true)
        try? files.removeItem(at: url(index: keep - 1))
        for index in stride(from: keep - 2, through: 0, by: -1) where files.fileExists(atPath: path(index)) {
            try files.moveItem(at: url(index: index), to: url(index: index + 1))
        }
        guard files.createFile(atPath: path(0), contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return try FileHandle(forWritingTo: latest)
    }

    private func path(_ index: Int) -> String {
        url(index: index).path(percentEncoded: false)
    }
}
