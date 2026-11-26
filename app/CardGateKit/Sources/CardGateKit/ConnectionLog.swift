public import Foundation

/// How a client log line is shown in the detailed log: by its level, except for warnings and errors
/// known to be harmless (limits of FreeRDP on macOS, the clean-up after the user disconnected).
public enum LogLineKind: Equatable, Sendable {
    case normal
    case harmless
    case warning
    case error
}

/// What happened during a connection, in words the user understands (the log window's "important
/// messages only" view). The detailed log keeps the client's own lines.
public enum ConnectionLogEvent: Equatable, Sendable {
    case connecting
    case signingInToGateway
    case gatewayAccepted
    /// The security negotiated with the computer; RDP security (RC4) is weaker.
    case security(SecurityMethod)
    case desktopShown
    case signedIn
    /// The user trusted the computer's changed certificate (its fingerprint) for this connection.
    case changedCertificateTrusted
    /// With NLA, Kerberos verified the computer whose certificate was renewed; the new one is kept.
    case renewedCertificateVerified
    case connectionInterrupted
    /// The gateway ended the connection when its time limit ran out (or its re-authentication
    /// failed); the client reconnects.
    case gatewaySessionExpired
    /// Playing the sound of the remote computer failed (e.g. the audio device went away).
    case soundFailed
    case reconnecting(attempt: Int, total: Int)
    case reconnected
    /// An attempt to restore the connection failed for a reason the user can act on (e.g. no card).
    case reconnectFailed(SessionFailure)
    /// The card was taken out of the reader redirected to the computer, or put back.
    case cardRemoved
    case cardInserted
    /// The desktop scale was changed in the title bar: a percentage, or `nil` for each display's own.
    case scaleChanged(Int?)
    case ended(SessionEnd)
    /// A warning or error the app does not know, with the client's text (level and source dropped).
    case unknown(String, isError: Bool)

    public enum Severity: Equatable, Sendable {
        case info
        case warning
        case error
    }

    public var severity: Severity {
        switch self {
        case .security(.rdp), .changedCertificateTrusted, .connectionInterrupted, .gatewaySessionExpired, .soundFailed,
            .reconnectFailed, .cardRemoved:
            .warning
        case .ended(.closedByUser):
            .info
        case .ended(.failed(.sessionTakenOver)), .ended(.failed(.idleTimeout)),
            .ended(.failed(.disconnectedByServer)):
            .warning
        case .ended(.failed):
            .error
        case .unknown(_, let isError):
            isError ? .error : .warning
        default:
            .info
        }
    }
}

/// The log of one connection as the log window shows it: the kind of each client line and the
/// important events. Feed the client's lines in order; some depend on what happened before.
public struct ConnectionLog: Equatable, Sendable {
    public struct Entry: Identifiable, Equatable, Sendable {
        public let id: Int
        /// "16:55:05", the time of the client line or of the app's event.
        public let time: String
        public let event: ConnectionLogEvent
    }

    public private(set) var entries: [Entry] = []
    /// Changes whenever `entries` changes (cheaper to compare than the entries).
    public private(set) var revision = 0
    private var nextID = 0
    /// Kerberos problems of the sign-in to the computer (NLA): WinPR may recover from them, so they
    /// are listed only when the connection then fails, before its end.
    private var kerberosProblems: [Entry] = []
    /// The gateway accepted the card in this connection attempt: certificate warnings that follow
    /// are the computer's (its own certificate, trusted on first use).
    private var pastGateway = false
    /// The user or the computer ended the session: errors of closing the connection are expected.
    private var ending = false
    private var desktopShown = false
    private var signedIn = false
    /// Between a broken connection and its restoration (or the end): the steps of reconnecting and
    /// its errors are summed up by the interruption and the result.
    private var interrupted = false
    /// The entry of this outage's reconnection failure (`reconnectFailed`), if one was listed.
    private var reconnectFailureEntry: Int?
    /// An unknown line is not shown endlessly (e.g. repeated by every redraw).
    static let maxEntries = 500

    /// The client reconnects after an outage (`FreeRDPCommand.reconnects`); without it an outage
    /// ends the session, which the end event reports.
    private let reconnects: Bool
    /// The previous line reported a problem with the computer's certificate; its subject follows.
    private var afterCertificateProblem = false
    /// Whether the card is in the redirected reader, once a change was reported.
    private var cardPresent: Bool?
    /// The gateway said it ends the session (time limit, re-authentication); the outage follows.
    /// The time of its line ("16:38:29"): only an outage right after it is the gateway's doing.
    private var gatewayEndsSession: String?
    private var soundFailed = false

    public init(reconnects: Bool = true) {
        self.reconnects = reconnects
    }

    /// Classifies a client line and notes the event it reports, if any.
    public mutating func consume(_ line: String) -> LogLineKind {
        // A line that ends the session is already part of its ending.
        noteState(line)
        let kind = kind(of: line)
        afterCertificateProblem = kind == .harmless && line.contains(Self.certificateProblem)
        if let event = event(in: line) {
            add(event, time: Self.time(of: line))
        } else if kind == .warning || kind == .error, !interrupted {
            let problem = ConnectionLogEvent.unknown(Self.message(of: line), isError: kind == .error)
            if Self.isKerberos(line) {
                // After the desktop appeared they are not about signing in; the end says the rest.
                guard !desktopShown else { return kind }
                // The last ones say why it failed.
                kerberosProblems.append(Entry(id: -1, time: Self.time(of: line), event: problem))
                if kerberosProblems.count > 20 { kerberosProblems.removeFirst() }
            } else if !Self.explainedElsewhere(line) {
                add(problem, time: Self.time(of: line))
            }
        }
        return kind
    }

    /// An event of the app (start, the end the user sees in the window).
    public mutating func note(_ event: ConnectionLogEvent, at date: Date = .now) {
        if case .ended(let end) = event {
            interrupted = false
            ending = true
            if case .failed(let failure) = end {
                // The end says it again.
                if let index = entries.lastIndex(where: { $0.id == reconnectFailureEntry }),
                    entries[index].event == .reconnectFailed(failure)
                {
                    entries.remove(at: index)
                    revision += 1
                }
                if !Self.saidByKerberos.contains(failure) {
                    for problem in kerberosProblems { add(problem.event, time: problem.time) }
                }
            }
            kerberosProblems = []
        }
        add(event, time: Self.timeFormat.string(from: date))
    }

    /// The card was taken out of the redirected reader (`false`) or put back. Only changes are
    /// listed; the card is in the reader when connecting.
    public mutating func cardInReader(_ present: Bool, at date: Date = .now) {
        guard present != (cardPresent ?? true) else { return }
        cardPresent = present
        let time = Self.timeFormat.string(from: date)
        if !present {
            // macOS may report the removal a moment after the client passed Windows the answers it caused.
            let now = Self.seconds(of: time)
            while let last = entries.last, case .unknown(let text, _) = last.event,
                Self.readerGoneCodes.contains(where: text.contains), let then = Self.seconds(of: last.time),
                let now, (now - then + 86_400) % 86_400 <= 5
            {
                entries.removeLast()
                revision += 1
            }
        }
        add(present ? .cardInserted : .cardRemoved, time: time)
    }

    /// Why reconnecting failed (`SessionLogParser.reconnectFailure`, from `line`): listed once per
    /// outage, not after the user disconnected.
    public mutating func reconnectFailed(_ failure: SessionFailure, line: String) {
        guard interrupted, !ending, reconnectFailureEntry == nil else { return }
        reconnectFailureEntry = nextID
        add(.reconnectFailed(failure), time: Self.time(of: line))
    }

    /// CardGate stopped the client (Disconnect, Cancel, quitting).
    public mutating func stopRequested() {
        ending = true
    }

    private mutating func add(_ event: ConnectionLogEvent, time: String) {
        guard entries.count < Self.maxEntries || !Self.isUnknown(event) else { return }
        entries.append(Entry(id: nextID, time: time, event: event))
        nextID += 1
        revision += 1
    }

    // MARK: - Line kinds

    func kind(of line: String) -> LogLineKind {
        let level: LogLineKind =
            if line.contains("[ERROR]") || line.contains("[FATAL]") {
                .error
            } else if line.contains("[WARN]") {
                .warning
            } else {
                .normal
            }
        guard level != .normal else { return .normal }
        if Self.harmless.contains(where: line.contains) || Self.isCardRemovedAnswer(line)
            || (cardPresent == false && Self.isReaderGoneAnswer(line))
        {
            return .harmless
        }
        if ending, Self.harmlessWhenEnding.contains(where: line.contains) { return .harmless }
        if pastGateway,
            line.contains(Self.certificateProblem) || (afterCertificateProblem && line.contains("[verify_cb]: CN ="))
        {
            return .harmless
        }
        return level
    }

    /// Warnings and errors that do not mean anything went wrong.
    static let harmless = [
        // Sign-in with Microsoft Entra ID, not used.
        "This build does not support AAD security",
        // The client warns about every secret option; the PIN is never on the command line.
        "[warn_credential_args]",
        // Missing optimizations and thread priorities of FreeRDP on macOS.
        "Implement neon optimized version",
        "pthread_setschedprio",
        // The Kerberos library does not offer optional details; the sign-in works without them.
        "krb5_get_etype_info",
        "QueryContextAttributes implement ulAttribute=0x00000456",
        "QueryContextAttributesA status SEC_E_UNSUPPORTED_FUNCTION",
        // A clipboard format that cannot be converted to another one (e.g. an image to HTML): the
        // other side gets the formats that can.
        "No synthesizer for format",
        // Windows started work with the card and left it unfinished; the client ends it as Windows does.
        "ending it and resetting the card like Windows does",
        // The user cancelled or disconnected, or signed out or disconnected in Windows.
        "ERRCONNECT_CONNECT_CANCELLED",
        "ERRINFO_LOGOFF_BY_USER",
        "ERRINFO_RPC_INITIATED_DISCONNECT_BY_USER",
    ]

    /// Errors of closing the connection after the user or the computer ended the session.
    static let harmlessWhenEnding = [
        "Connection aborted by user",
        "Autoreconnect aborted by user",
        "Unhandled SSL error",
        "BIO_should_retry retries exceeded",
        "DisconnectProviderUltimatum",
        "CHANNEL_RC_BAD_CHANNEL_HANDLE",
    ]

    /// The computer's certificate (self-signed, or from an internal certification authority) is
    /// trusted on first use (`/cert:tofu`): its fingerprint decides, a changed one is an error of its
    /// own. Its subject line follows. The gateway's certificate must be trusted by the system and is
    /// checked before the card is used, so a problem there stays a warning.
    static let certificateProblem = "[verify_cb]: Certificate verification failure"

    // MARK: - Events

    private mutating func noteState(_ line: String) {
        if line.contains("RD Gateway smart card authentication done") { pastGateway = true }
        if desktopShown, !interrupted, Self.gatewaySessionEnd.contains(where: line.contains) {
            gatewayEndsSession = Self.time(of: line)
        }
        if line.contains("Attempting reconnect (") { pastGateway = false }
        if line.contains("disconnect confirmed by the user") || line.contains("ERRCONNECT_CONNECT_CANCELLED")
            || line.contains("Credential prompt cancelled") || line.contains("Autoreconnect aborted by user")
            || line.contains("ERRINFO_")
        {
            ending = true
        }
    }

    private mutating func event(in line: String) -> ConnectionLogEvent? {
        if let event = reconnectEvent(in: line) { return event }
        if interrupted { return nil }  // the steps of reconnecting
        return sessionProblem(in: line) ?? connectionStep(in: line)
    }

    /// An outage and how the client restores the connection.
    private mutating func reconnectEvent(in line: String) -> ConnectionLogEvent? {
        if line.contains("Network disconnect!") {
            guard reconnects, !ending, desktopShown, !interrupted else { return nil }
            // What broke the connection just before is the interruption itself; problems from before
            // stay listed.
            let now = Self.seconds(of: Self.time(of: line))
            while let last = entries.last, Self.isUnknown(last.event),
                let then = Self.seconds(of: last.time), let now, (now - then + 86_400) % 86_400 <= 5
            {
                entries.removeLast()
                revision += 1
            }
            interrupted = true
            reconnectFailureEntry = nil
            return interruption(at: line)
        }
        if let attempt = Self.numbers(in: line, after: "Attempting reconnect (") {
            // The client also reconnects after some errors of the computer, without an outage.
            if !interrupted, desktopShown {
                add(interruption(at: line), time: Self.time(of: line))
                reconnectFailureEntry = nil
            }
            interrupted = true
            ending = false
            // The client counts the attempts from 0.
            return .reconnecting(attempt: attempt.0 + 1, total: attempt.1)
        }
        if line.contains("Reconnected (attempt") {
            // A new connection: how the previous one ended no longer applies.
            interrupted = false
            ending = false
            reconnectFailureEntry = nil
            return .reconnected
        }
        return nil
    }

    /// Why the connection broke, if the gateway said so.
    private mutating func interruption(at line: String) -> ConnectionLogEvent {
        defer { gatewayEndsSession = nil }
        guard let then = gatewayEndsSession.flatMap(Self.seconds(of:)), let now = Self.seconds(of: Self.time(of: line))
        else { return .connectionInterrupted }
        return (now - then + 86_400) % 86_400 <= 5 ? .gatewaySessionExpired : .connectionInterrupted
    }

    /// A problem while the desktop is shown that does not end the session.
    private mutating func sessionProblem(in line: String) -> ConnectionLogEvent? {
        guard desktopShown, !soundFailed, Self.soundFailure.contains(where: line.contains) else { return nil }
        soundFailed = true  // the client closes the device; once is enough
        return .soundFailed
    }

    private mutating func connectionStep(in line: String) -> ConnectionLogEvent? {
        if line.contains("smart card ready for RD Gateway authentication") { return .signingInToGateway }
        if line.contains("RD Gateway smart card authentication done") { return .gatewayAccepted }
        if let method = SessionLogParser.negotiatedMethod(in: line) { return .security(method) }
        if line.contains("confirmed by its fingerprint, replacing the stored one") {
            return .changedCertificateTrusted
        }
        if line.contains("verified by Kerberos, replacing the stored one") { return .renewedCertificateVerified }
        if let range = line.range(of: "[changeScale]: " + TitleBarControls.scaleChange + ": ") {
            let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
            if value == TitleBarControls.displayScale { return .scaleChanged(nil) }
            if let percent = Int(value) { return .scaleChanged(percent) }
        }
        if line.contains("[gdi_init_ex]"), !desktopShown {
            desktopShown = true
            kerberosProblems = []  // the sign-in to the computer succeeded
            return .desktopShown
        }
        if line.contains("signed in: releasing the modifier keys"), !signedIn {
            signedIn = true
            return .signedIn
        }
        return nil
    }

    /// Warnings and errors the user learns about otherwise: the failure the window shows (the end
    /// event), or a step that is not a problem by itself.
    static func explainedElsewhere(_ line: String) -> Bool {
        SessionLogParser.failure(in: line) != nil || line.contains("ERRINFO_")
            || SessionLogParser.gatewayTemporarilyUnavailable(line) || explained.contains(where: line.contains)
            // Said by the interruption (`gatewaySessionExpired`) or the sound event.
            || gatewaySessionEnd.contains(where: line.contains) || soundFailure.contains(where: line.contains)
            || (line.contains("[list_provider_keys]") && line.contains("no certificates found"))
    }

    /// Failures named after what Kerberos said: its own lines are left to the detailed log.
    static let saidByKerberos: Set<SessionFailure> = [
        .clockSkew, .domainUnreachable, .computerUnknownToDomain, .accountUnknownToDomain, .accountRevoked,
        .domainNotTrusted, .cardCertificateRejected,
    ]

    /// The gateway ends the session: its time limit ran out, or it asked to sign in again and that failed.
    static let gatewaySessionEnd = ["E_PROXY_SESSIONTIMEOUT", "E_PROXY_REAUTH_"]

    /// The macOS sound output failed; the client closes it (sound is back in the next session).
    static let soundFailure = ["audio output failed, dropping sound", "Failed to start audio player"]

    /// A line of the Kerberos sign-in to the computer (NLA).
    static func isKerberos(_ line: String) -> Bool {
        line.contains("[com.winpr.sspi.Kerberos]") || SessionLogParser.isKerberosError(line)
    }

    static let explained = [
        // The security the computer accepts, and its changed certificate: the end event says it.
        "nego_process_negotiation_failure",
        "changed since it was first trusted",
        // The client's own message about how the session ended (the end event says it).
        "[handleShow]: Terminate with",
        // Consequences of a failure the end event names (a cancelled PIN, a computer that cannot be
        // reached), and the stack traces the client logs with some of them.
        "[nego_connect]: Failed to connect",
        "Error: protocol security negotiation or connection failure",
        "BIO_read returned an error",
        "Unsupported BIO_CTRL",
        "[winpr_log_backtrace_ex]",
    ]

    static func isUnknown(_ event: ConnectionLogEvent) -> Bool {
        if case .unknown = event { true } else { false }
    }

    // MARK: - Parsing

    /// "[16:55:05:261] [81611:fe0ed0c1] [WARN][…" → "16:55:05".
    static func time(of line: String) -> String {
        guard let range = line.range(of: #"^\[\d{2}:\d{2}:\d{2}"#, options: .regularExpression) else {
            return timeFormat.string(from: .now)
        }
        return String(line[range].dropFirst())
    }

    /// The text of a client line without its time, thread and source:
    /// "[…][WARN][com.freerdp.crypto] - [verify_cb]: CN = x" → "CN = x".
    static func message(of line: String) -> String {
        guard let range = line.range(of: #"\] - \[[^\]]*\]: "#, options: .regularExpression) else {
            return line
        }
        return String(line[range.upperBound...])
    }

    /// "16:55:05" → seconds since midnight.
    static func seconds(of time: String) -> Int? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }

    /// "Attempting reconnect (2 of 10)" → (2, 10).
    static func numbers(in line: String, after prefix: String) -> (Int, Int)? {
        guard let start = line.range(of: prefix) else { return nil }
        let parts = line[start.upperBound...].prefix { $0 != ")" }.split(separator: " ")
        guard parts.count == 3, parts[1] == "of", let first = Int(parts[0]), let second = Int(parts[2]) else {
            return nil
        }
        return (first, second)
    }

    static let timeFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
