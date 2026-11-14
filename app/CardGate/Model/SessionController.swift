import AppKit
import CardGateKit
import OSLog
import Observation

/// Runs the bundled FreeRDP client and follows its progress through the log it writes.
@MainActor
@Observable
final class SessionController {
    /// `nil` before the first connection.
    private(set) var phase: SessionPhase?
    /// Recent client log lines for the log window (never contains the PIN; the client never logs it).
    private(set) var log = LogBuffer(capacity: 5000)

    private var process: Process?
    /// The last sessions' logs are also kept in files for support (never contain the PIN).
    private var logFile: FileHandle?
    static let logFiles = SessionLogFiles.standard
    private var parser = SessionLogParser()
    private let logger = Logger(subsystem: "io.github.jk-sw.cardgate", category: "session")

    /// The gateway is being checked before the client starts.
    private var preflight: Task<Void, Never>?
    /// Keeps the Mac awake while the client runs (CardGate → Settings); the display may turn off.
    @ObservationIgnored private var awake: (any NSObjectProtocol)? {
        didSet { oldValue.map(ProcessInfo.processInfo.endActivity) }
    }
    /// How the PIN dialog of the current session ended, if it did not deliver a PIN.
    private var pinOutcome: PINPrompt.Event?
    /// Names the current connection in the messages of its PIN dialog (`PINDialogMessages`).
    private var pinSession: String?

    var isRunning: Bool { process != nil || preflight != nil }
    /// Cancel or Disconnect was chosen; the client is quitting (see `ClientStop`).
    private(set) var isStopping = false

    /// The running client (an agent app without a Dock icon), to bring its window forward.
    var clientApplication: NSRunningApplication? {
        process.flatMap { NSRunningApplication(processIdentifier: $0.processIdentifier) }
    }

    /// Called when a connection reached the remote desktop and when a session ended.
    var onConnected: (() -> Void)?
    var onEnded: ((SessionEnd) -> Void)?

    init() {
        let center = DistributedNotificationCenter.default()
        for event in PINPrompt.Event.allCases {
            let handler: @Sendable (Notification) -> Void = { [weak self] notification in
                let sender = notification.object as? String
                Task { @MainActor in self?.pinPrompt(event, client: sender) }
            }
            center.addObserver(forName: event.notification, object: nil, queue: .main, using: handler)
        }
    }

    /// The PIN dialog runs in its own process and reports what happens to it. It names the
    /// connection it belongs to, so a dialog of another app instance or another process is ignored.
    private func pinPrompt(_ event: PINPrompt.Event, client: String?) {
        guard process != nil, let pinSession, PINDialogMessages.isFrom(session: pinSession, sender: client) else {
            return
        }
        if isStopping {
            // The client opened it after Cancel, before it ended: nobody should type a PIN now.
            if event == .shown { PINPrompt.close(session: pinSession) }
            return
        }
        switch (event, phase) {
        case (.shown, .starting?), (.shown, .authenticatingGateway?):
            parser.pinDialogShown()
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
    /// - Parameter preventSleep: keep the Mac awake until the client ends.
    func connect(_ command: FreeRDPCommand, gateway: HostAddress?, preventSleep: Bool = false) {
        guard !isRunning else { return }
        awake =
            preventSleep
            ? ProcessInfo.processInfo.beginActivity(
                options: .idleSystemSleepDisabled,
                reason: String(localized: "Remote desktop connection (CardGate)")) : nil
        log.removeAll()
        phase = .starting
        guard let gateway, let url = GatewayCheckResult.url(for: gateway) else {
            launch(command, gatewayTrusted: false)
            return
        }
        preflight = Task { [weak self] in
            let result = await GatewayCheckResult.probe(url)
            guard let self, !Task.isCancelled else { return }
            self.preflight = nil
            self.logger.info(
                "Gateway check \(url, privacy: .private(mask: .hash)): \(String(describing: result), privacy: .public)")
            switch result {
            case .untrusted:
                self.end(.failed(.untrustedCertificate))
            case .unreachable:
                self.end(.failed(.gatewayUnreachable))
            case .trusted, .unknown:
                self.launch(command, gatewayTrusted: result == .trusted)
            }
        }
    }

    private func launch(_ command: FreeRDPCommand, gatewayTrusted: Bool) {
        do {
            try start(command, gatewayTrusted: gatewayTrusted)
        } catch {
            logger.error("Cannot start client: \(error.localizedDescription, privacy: .public)")
            end(.failed(.other(error.localizedDescription)))
        }
    }

    /// Every way a connection attempt ends goes through here, so the app always learns about it.
    private func end(_ end: SessionEnd) {
        isStopping = false
        awake = nil
        phase = .ended(end)
        onEnded?(end)
    }

    /// - Parameter gatewayTrusted: the system trusted the gateway's certificate (`GatewayCheckResult`).
    private func start(_ command: FreeRDPCommand, gatewayTrusted: Bool) throws {
        guard process == nil else { return }

        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        let pinSession = PINDialogMessages.newSessionID()
        var environment = command.processEnvironment(inheriting: ProcessInfo.processInfo.environment)
        environment[PINDialogMessages.sessionVariable] = pinSession
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let (exits, exitContinuation) = AsyncStream<(status: Int32, crashed: Bool)>.makeStream()
        process.terminationHandler = { finished in
            exitContinuation.yield((finished.terminationStatus, finished.terminationReason == .uncaughtSignal))
            exitContinuation.finish()
        }

        parser = SessionLogParser(gatewayTrustedBySystem: gatewayTrusted, reconnects: command.reconnects)
        pinOutcome = nil
        // Addresses and names stay out of the system log (they end up in diagnostics reports); the
        // connection log file gets the full command line.
        logger.info("Starting client (\(command.arguments.count) arguments)")
        try process.run()
        self.process = process
        self.pinSession = pinSession
        // Only now: a client that cannot start would leave an empty log and push out an old one.
        logFile = Self.openLogFile()
        try? logFile?.write(contentsOf: Data("CardGate: \(command.arguments.joined(separator: " "))\n".utf8))

        let reader = OutputReader()
        Task { [weak self] in
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    // A process the client started (the PIN dialog) may keep the pipe open after
                    // the client ended; what it writes then belongs to no session.
                    guard self?.process === process else { break }
                    self?.receive(line)
                }
            } catch {
                self?.logger.error("Reading client output failed: \(error.localizedDescription, privacy: .public)")
            }
            reader.done = true
        }
        // The session ends when the client exits, not when its output closes (see above); the last
        // lines (the reason it ended) get a moment to arrive.
        Task { [weak self] in
            for await exit in exits {
                var waited = 0
                while !reader.done, waited < 20 {
                    try? await Task.sleep(for: .milliseconds(50))
                    waited += 1
                }
                self?.finished(status: exit.status, crashed: exit.crashed)
            }
        }
    }

    /// Whether the client's output was read to its end.
    @MainActor
    private final class OutputReader {
        var done = false
    }

    /// Forgets the result of a finished connection (e.g. after the card was replaced).
    func clearFinished() {
        if process == nil, case .ended = phase { phase = nil }
    }

    /// Cancels the connection attempt or disconnects: cancels the gateway check, or asks the client
    /// to quit and kills it if it does not (`ClientStop`). An open PIN dialog closes at once.
    func stop() {
        if let preflight {
            preflight.cancel()
            self.preflight = nil
            end(.closedByUser)
        }
        guard let process, !isStopping else { return }
        isStopping = true
        parser.stopRequested()
        let pid = process.processIdentifier
        if let pinSession { PINPrompt.close(session: pinSession) }
        Task { [weak self] in
            await ClientStop.run(
                connected: self?.phase?.hasDesktop == true,
                terminate: { process.terminate() },
                isRunning: { self?.process === process && process.isRunning },
                kill: {
                    self?.logger.error("Client did not quit, killing it")
                    Darwin.kill(pid, SIGKILL)
                })
        }
    }

    private func receive(_ line: String) {
        log.append(line)
        // A full disk must not crash the app; the log window still has the line.
        try? logFile?.write(contentsOf: Data((line + "\n").utf8))
        if let next = parser.consume(line) {
            let restored = phase == .reconnecting
            let appears = next.desktopAppears(after: phase)
            phase = next
            if appears { onConnected?() }
            if next == .reconnecting {
                logger.info("Session reconnecting")
            } else if restored, next == .connected {
                logger.info("Session restored")
            }
        }
    }

    private func finished(status: Int32, crashed: Bool) {
        process = nil
        pinSession = nil
        try? logFile?.close()
        logFile = nil
        logger.info("Client exited with \(crashed ? "signal" : "status", privacy: .public) \(status)")
        var result: SessionEnd
        if case .ended(let end) = parser.processExited(status: status, crashed: crashed) {
            result = end
        } else {
            result = .failed(.other("exit status \(status)"))  // the parser always ends; never stay running
        }
        switch (pinOutcome, result) {
        case (.cancelled?, .failed):
            result = .closedByUser  // the user cancelled the PIN dialog
        case (.timedOut?, _):
            result = .failed(.pinTimedOut)
        default:
            break
        }
        end(result)
    }

    private static func openLogFile() -> FileHandle? {
        try? logFiles.startNew()
    }
}
