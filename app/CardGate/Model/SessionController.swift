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
    private var parser = SessionLogParser()
    private static let maxLogLines = 5000
    private let logger = Logger(subsystem: "io.github.jk-sw.cardgate", category: "session")

    var isRunning: Bool { process != nil }

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
        if log.count > Self.maxLogLines { log.removeFirst(log.count - Self.maxLogLines) }
        if let next = parser.consume(line) { phase = next }
    }

    private func finished(status: Int32) {
        process = nil
        phase = parser.processExited(status: status)
        logger.info("Client exited with status \(status)")
    }
}
