import CardGateKit
import Foundation
import OSLog
import Observation

/// Runs the bundled FreeRDP client and follows its progress through the log it writes.
@MainActor
@Observable
final class SessionController {
    /// `nil` before the first connection.
    private(set) var phase: SessionPhase?
    /// Recent client log lines for the log window (never contains the PIN; the client never logs it).
    private(set) var log: [String] = []

    private var process: Process?
    /// The last session's log is also kept in a file for support (never contains the PIN).
    private var logFile: FileHandle?
    static var logFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/CardGate/last-session.log")
    }
    private var parser = SessionLogParser()
    private static let maxLogLines = 5000
    private let logger = Logger(subsystem: "io.github.jk-sw.cardgate", category: "session")

    var isRunning: Bool { process != nil }

    init() {
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: PINPrompt.shownNotification, object: nil, queue: .main) { @Sendable [weak self] _ in
            Task { @MainActor in self?.pinPrompt(shown: true) }
        }
        center.addObserver(forName: PINPrompt.closedNotification, object: nil, queue: .main) {
            @Sendable [weak self] _ in
            Task { @MainActor in self?.pinPrompt(shown: false) }
        }
    }

    /// The PIN dialog runs in its own process and reports when it opens and closes.
    private func pinPrompt(shown: Bool) {
        guard isRunning else { return }
        switch (shown, phase) {
        case (true, .starting?), (true, .authenticatingGateway?):
            phase = .waitingForPIN
        case (false, .waitingForPIN?):
            phase = .authenticatingGateway
        default:
            break
        }
    }

    func start(_ command: FreeRDPCommand) throws {
        guard process == nil else { return }

        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        var environment = ProcessInfo.processInfo.environment
        environment.merge(command.environment) { _, new in new }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let (exits, exitContinuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { finished in
            exitContinuation.yield(finished.terminationStatus)
            exitContinuation.finish()
        }

        parser = SessionLogParser()
        log.removeAll()
        logFile = Self.openLogFile()
        phase = .starting
        logger.info("Starting client: \(command.arguments.joined(separator: " "), privacy: .public)")
        try process.run()
        self.process = process

        Task { [weak self] in
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    self?.receive(line)
                }
            } catch {
                self?.logger.error("Reading client output failed: \(error.localizedDescription, privacy: .public)")
            }
            for await status in exits {
                self?.finished(status: status)
            }
        }
    }

    /// Forgets the result of a finished connection (e.g. after the card was replaced).
    func clearFinished() {
        if process == nil, case .ended = phase { phase = nil }
    }

    /// Asks the client to disconnect and quit.
    func stop() {
        process?.terminate()
    }

    private func receive(_ line: String) {
        log.append(line)
        logFile?.write(Data((line + "\n").utf8))
        if log.count > Self.maxLogLines { log.removeFirst(log.count - Self.maxLogLines) }
        if let next = parser.consume(line) { phase = next }
    }

    private func finished(status: Int32) {
        process = nil
        try? logFile?.close()
        logFile = nil
        phase = parser.processExited(status: status)
        logger.info("Client exited with status \(status)")
    }

    private static func openLogFile() -> FileHandle? {
        let url = logFileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else { return nil }
        return try? FileHandle(forWritingTo: url)
    }
}
