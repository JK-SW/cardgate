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
    /// The last sessions' logs are also kept in files for support (never contain the PIN).
    private var logFile: FileHandle?
    static let logFiles = SessionLogFiles.standard
    private var parser = SessionLogParser()
    private static let maxLogLines = 5000
    private let logger = Logger(subsystem: "io.github.jk-sw.cardgate", category: "session")

    /// The gateway is being checked before the client starts.
    private var preflight: Task<Void, Never>?
    /// How the PIN dialog of the current session ended, if it did not deliver a PIN.
    private var pinOutcome: PINPrompt.Event?

    var isRunning: Bool { process != nil || preflight != nil }

    /// Called when a connection reached the remote desktop and when a session ended.
    var onConnected: (() -> Void)?
    var onEnded: ((SessionEnd) -> Void)?

    init() {
        let center = DistributedNotificationCenter.default()
        for event in PINPrompt.Event.allCases {
            let handler: @Sendable (Notification) -> Void = { [weak self] _ in
                Task { @MainActor in self?.pinPrompt(event) }
            }
            center.addObserver(forName: event.notification, object: nil, queue: .main, using: handler)
        }
    }

    /// The PIN dialog runs in its own process and reports what happens to it.
    private func pinPrompt(_ event: PINPrompt.Event) {
        guard process != nil else { return }
        switch (event, phase) {
        case (.shown, .starting?), (.shown, .authenticatingGateway?):
            phase = .waitingForPIN
        case (.submitted, .waitingForPIN?):
            phase = .authenticatingGateway
        case (.cancelled, _), (.timedOut, _):
            pinOutcome = event
        default:
            break
        }
    }

    /// Checks the gateway with the system's certificate trust (keychain, revocation) and starts
    /// the client only if it is trusted, so a bad certificate never reaches the card.
    func connect(_ command: FreeRDPCommand, gateway: HostAddress?) {
        guard !isRunning else { return }
        log.removeAll()
        phase = .starting
        guard let gateway, let url = GatewayCheckResult.url(for: gateway) else {
            launch(command)
            return
        }
        preflight = Task { [weak self] in
            let result = await Self.check(url)
            guard let self, !Task.isCancelled else { return }
            self.preflight = nil
            self.logger.info("Gateway check \(url, privacy: .public): \(String(describing: result), privacy: .public)")
            switch result {
            case .untrusted:
                self.phase = .ended(.failed(.untrustedCertificate))
            case .unreachable:
                self.phase = .ended(.failed(.gatewayUnreachable))
            case .trusted, .unknown:
                self.launch(command)
            }
        }
    }

    nonisolated private static func check(_ url: URL) async -> GatewayCheckResult {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        do {
            _ = try await session.data(for: request)
            return GatewayCheckResult(error: nil)
        } catch {
            return GatewayCheckResult(error: error)
        }
    }

    private func launch(_ command: FreeRDPCommand) {
        do {
            try start(command)
        } catch {
            logger.error("Cannot start client: \(error.localizedDescription, privacy: .public)")
            phase = .ended(.failed(.other(error.localizedDescription)))
        }
    }

    private func start(_ command: FreeRDPCommand) throws {
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
        pinOutcome = nil
        logFile = Self.openLogFile()
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

    /// Asks the client to disconnect and quit (or cancels the gateway check).
    func stop() {
        if let preflight {
            preflight.cancel()
            self.preflight = nil
            phase = .ended(.closedByUser)
        }
        process?.terminate()
    }

    private func receive(_ line: String) {
        log.append(line)
        logFile?.write(Data((line + "\n").utf8))
        if log.count > Self.maxLogLines { log.removeFirst(log.count - Self.maxLogLines) }
        if let next = parser.consume(line) {
            phase = next
            if next == .connected { onConnected?() }
        }
    }

    private func finished(status: Int32) {
        process = nil
        try? logFile?.close()
        logFile = nil
        phase = parser.processExited(status: status)
        switch (pinOutcome, phase) {
        case (.cancelled?, .ended(.failed)?):
            phase = .ended(.closedByUser)  // the user cancelled the PIN dialog
        case (.timedOut?, .ended?):
            phase = .ended(.failed(.pinTimedOut))
        default:
            break
        }
        if case .ended(let end)? = phase { onEnded?(end) }
        logger.info("Client exited with status \(status)")
    }

    private static func openLogFile() -> FileHandle? {
        try? logFiles.startNew()
    }
}
