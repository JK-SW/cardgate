import Foundation

/// Progress of a connection as reported by the FreeRDP client log.
public enum SessionPhase: Equatable, Sendable {
    case starting
    /// The PIN dialog is open.
    case waitingForPIN
    /// Signing in to the gateway with the card.
    case authenticatingGateway
    case connectingComputer
    /// The remote desktop is shown.
    case connected
    /// The connection broke; the client is connecting again (its window stays open).
    case reconnecting
    case ended(SessionEnd)

    /// The remote desktop appears for the first time in this session (`previous` is the phase
    /// before), not again after the client reconnected.
    public func desktopAppears(after previous: SessionPhase?) -> Bool {
        self == .connected && previous != .reconnecting
    }

    /// The remote desktop window is open: the session is up or being restored.
    public var hasDesktop: Bool {
        self == .connected || self == .reconnecting
    }
}

public enum SessionEnd: Equatable, Sendable {
    /// The user closed the window or disconnected.
    case closedByUser
    case failed(SessionFailure)
}

public enum SessionFailure: Equatable, Sendable {
    /// No usable certificate on the card (card not inserted, reader asleep, wrong middleware).
    case noCertificate
    /// The PIN was rejected.
    case wrongPIN
    /// The card is locked after too many wrong PINs.
    case cardLocked
    /// The card refused the sign-in with an error that does not say why: maybe a wrong PIN, maybe a
    /// failing card or reader. The PIN is not offered again.
    case cardRefusedLogin
    case gatewayUnreachable
    case gatewayDenied
    /// The gateway's TLS certificate is not trusted (possible interception).
    case untrustedCertificate
    /// This Mac trusts the gateway's certificate, the client does not: the client trusts only public
    /// certification authorities, not certificates an organization installed in the keychain.
    case gatewayCertificateNotPublic
    /// The card holds more than one certificate usable for sign-in.
    case multipleCertificates
    /// The gateway's certificate changed during the session: it is not reconnected to (the card is
    /// used only with the certificate checked before connecting).
    case gatewayCertificateChanged
    /// The card's key is not an RSA key; signing in to the gateway supports only RSA.
    case unsupportedCardKey
    /// The PIN was not entered in time.
    case pinTimedOut
    case computerUnreachable
    /// The computer answered but refuses the connection security CardGate uses (needs TLS or NLA).
    case securityRefused
    /// The connection broke while working (network outage, gateway restart).
    case connectionLost
    /// Someone signed in to the computer, or the user connected to it from another device.
    case sessionTakenOver
    /// The computer ended an idle session.
    case idleTimeout
    /// An administrator or the computer itself ended the session (e.g. before a restart).
    case disconnectedByServer
    /// Any other error; carries FreeRDP's error name (e.g. `ERRCONNECT_CONNECT_TRANSPORT_FAILED`).
    case other(String)
}

/// Turns FreeRDP log lines into session phases. Feed lines in order; the parser keeps state
/// because the meaning of some lines depends on what happened before.
public struct SessionLogParser: Sendable {
    public private(set) var phase: SessionPhase = .starting
    private var failure: SessionFailure?
    /// Why the computer ended the session, if it said so (Windows sends an error info code).
    private var serverEnd: SessionEnd?
    /// CardGate itself ended the client (Disconnect, quitting): what follows is not an error.
    private var stoppedByApp = false
    /// The computer sent a negotiation failure (e.g. it requires TLS or NLA): it was reached.
    private var negotiationRefused = false
    /// The PIN dialog was shown: the client had reached the gateway (the sign-in line follows only
    /// after the card login).
    private var pinRequested = false
    /// The system trusted the gateway's certificate before the client started (`GatewayCheckResult`).
    private let gatewayTrustedBySystem: Bool
    /// The connection of a shown desktop broke ("Network disconnect!"); the client may reconnect.
    private var connectionBroke = false
    /// Why reconnecting failed, if the client said so.
    private var reconnectFailure: SessionFailure?
    /// The client reconnects after an outage (`FreeRDPCommand.reconnects`); without it an outage
    /// ends the session at once.
    private let reconnects: Bool

    public init(gatewayTrustedBySystem: Bool = false, reconnects: Bool = true) {
        self.gatewayTrustedBySystem = gatewayTrustedBySystem
        self.reconnects = reconnects
    }

    /// Processes one log line and returns the new phase if it changed.
    @discardableResult
    public mutating func consume(_ line: String) -> SessionPhase? {
        guard var next = nextPhase(for: line) else { return nil }
        // After CardGate stopped the client only a reconnection failure from before still counts.
        if stoppedByApp, case .ended(.failed(let failure)) = next, failure != reconnectFailure {
            next = .ended(.closedByUser)
        }
        guard next != phase else { return nil }
        if case .ended = phase { return nil }  // terminal
        phase = next
        return next
    }

    /// CardGate asked the client to quit (Disconnect, quitting the app): whatever it logs or how it
    /// exits after that is not an error. An error it reported before is still shown (e.g. a wrong
    /// PIN – the user must know an attempt was used).
    public mutating func stopRequested() {
        stoppedByApp = true
    }

    /// The client asked for the PIN (its dialog reports it to the app, the log does not).
    public mutating func pinDialogShown() {
        pinRequested = true
    }

    /// Called when the client process exited.
    /// - Parameters:
    ///   - status: the exit status, or the signal number when `crashed`.
    ///   - crashed: a signal ended the client (`Process.terminationReason == .uncaughtSignal`).
    public mutating func processExited(status: Int32, crashed: Bool = false) -> SessionPhase {
        if case .ended = phase { return phase }
        // An error logged while connecting is outdated once the desktop was shown.
        let failure = phase.hasDesktop ? nil : failure
        if stoppedByApp {
            // A PIN attempt used while reconnecting is still reported.
            phase = (failure ?? reconnectFailure).map { .ended(.failed($0)) } ?? .ended(.closedByUser)
            return phase
        }
        if phase.hasDesktop, let serverEnd {
            phase = .ended(serverEnd)  // e.g. signed out in Windows: the client just exits
        } else if let failure {
            phase = .ended(.failed(failure))
        } else if crashed, !Self.quitSignals.contains(status) {
            // A crash is never a normal end, not even after the desktop was shown or while
            // reconnecting (CardGate's own kill after Disconnect is handled above).
            phase = .ended(.failed(.other("signal \(status)")))
        } else if phase.hasDesktop, connectionBroke {
            // Not reconnecting (turned off), or it gave up.
            phase = .ended(.failed(reconnectFailure ?? .connectionLost))
        } else if phase.hasDesktop || status == 0 {
            phase = .ended(.closedByUser)
        } else {
            phase = .ended(.failed(.other("exit status \(status)")))
        }
        return phase
    }

    /// Signals that ask a process to quit (`killall`, logout, closing a terminal): not a crash.
    static let quitSignals: Set<Int32> = [SIGTERM, SIGINT, SIGHUP]

    /// Texts of the FreeRDP log this parser depends on. A test checks that the bundled client still
    /// contains them, so a FreeRDP update cannot silently break the status display.
    public static let logMarkers = [
        "smart card ready for RD Gateway authentication",
        "RD Gateway smart card authentication done",
        "gdi_init_ex",
        "registered [",
        "no suitable smartcard certificates",
        "more than one suitable smartcard certificate",
        "FREERDP_SMARTCARD_CERT_SHA1",
        "WRONG PIN",
        "PIN is LOCKED",
        "certificate not trusted",
        "inner TLS certificate differs",
        "Network disconnect!",
        "Attempting reconnect (",
        "Reconnected (attempt",
        "Autoreconnect aborted by user",
        "- not retrying",
        "RD Gateway certificate changed",
        "client certificate has no RSA key",
        "Credential prompt cancelled",
        "ERRCONNECT_CONNECT_CANCELLED",
        "ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED",
        "ERRCONNECT_CONNECT_TRANSPORT_FAILED",
        "ERRINFO_LOGOFF_BY_USER",
        "ERRINFO_LOGON_TIMEOUT",
        "nego_process_negotiation_failure",
        "ERRCONNECT_HYBRID_REQUIRED_BY_SERVER",
        "ERRINFO_RPC_INITIATED_LOGOFF",
        "ERRINFO_DISCONNECTED_BY_OTHER_CONNECTION",
        "ERRINFO_RPC_INITIATED_DISCONNECT_BY_USER",
        "ERRINFO_IDLE_TIMEOUT",
        "ERRINFO_RPC_INITIATED_DISCONNECT",
    ]

    private mutating func nextPhase(for line: String) -> SessionPhase? {
        // Reconnecting goes through the connection steps again: they are not shown.
        if phase.hasDesktop {
            return endOfConnectedSession(line)
        }
        if line.contains("smart card ready for RD Gateway authentication") {
            return .authenticatingGateway
        }
        if line.contains("RD Gateway smart card authentication done") {
            return .connectingComputer
        }
        if line.contains("[gdi_init_ex]") || line.contains("registered [smartcard] device") {
            return .connected
        }
        // The user cancelled the PIN dialog (or it timed out): the client gives up (patched FreeRDP).
        if line.contains("Credential prompt cancelled") {
            return .ended(.closedByUser)
        }
        if line.contains("nego_process_negotiation_failure") {
            negotiationRefused = true
        }
        if !stoppedByApp, var failure = Self.failure(in: line) {
            // The gateway accepted the sign-in, then the connection to the computer failed. If the
            // computer answered with a negotiation failure it was reached but refuses the security;
            // otherwise the gateway closed the channel without a reason: it could not reach the
            // computer (name mistyped or unknown, computer off or offline – it does not say which).
            if phase == .connectingComputer, failure == .other("ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED") {
                failure = negotiationRefused ? .securityRefused : .computerUnreachable
            }
            // A broken transport (the only source of `computerUnreachable` in the table) is the
            // computer's only after the gateway accepted the sign-in. Before the PIN was asked for,
            // the connection to the gateway could not be set up (e.g. TLS); after, it broke.
            if failure == .computerUnreachable, phase != .connectingComputer {
                failure = phase == .starting && !pinRequested ? .gatewayUnreachable : .connectionLost
            }
            self.failure = self.failure ?? refined(failure, line: line)
            return nil
        }
        return nil
    }

    /// How a session that reached the desktop goes on or ends. Closing the window, Disconnect in the
    /// Dock or quitting log a cancel first; signing out in Windows sends an error info code; a broken
    /// connection logs only the transport error and "Network disconnect!", then the client reconnects
    /// (if set) or exits.
    private mutating func endOfConnectedSession(_ line: String) -> SessionPhase? {
        // A failure of the reconnection the user has to know about (a PIN attempt used, an untrusted
        // gateway) is still shown when they then close the window.
        if line.contains("ERRCONNECT_CONNECT_CANCELLED") || line.contains("Credential prompt cancelled")
            || line.contains("Autoreconnect aborted by user")
        {
            return .ended(reconnectFailure.map { .failed($0) } ?? .closedByUser)
        }
        if let range = line.range(of: #"ERRINFO_[A-Z0-9_]+"#, options: .regularExpression) {
            serverEnd = serverEnd ?? Self.serverEnd(String(line[range]))
            return nil
        }
        if line.contains("Network disconnect!") {
            // Windows said why, or CardGate stopped it: the client does not reconnect.
            if let serverEnd { return .ended(serverEnd) }
            if stoppedByApp { return .ended(.closedByUser) }
            // Without reconnecting the client just quits; say so now, not only when it has exited.
            guard reconnects else { return .ended(.failed(.connectionLost)) }
            connectionBroke = true
            return nil
        }
        // Also after errors the client reconnects on its own (e.g. a failed graphics subsystem).
        if line.contains("Attempting reconnect (") {
            // What ended the connection before is not why reconnecting fails.
            if phase == .connected { serverEnd = nil }
            connectionBroke = true
            return .reconnecting
        }
        if line.contains("Reconnected (attempt") {
            // A new connection: what ended or failed before no longer applies.
            connectionBroke = false
            reconnectFailure = nil
            serverEnd = nil
            return .connected
        }
        // The first failure the user has to act on; network errors of the attempts before do not hide it.
        if phase == .reconnecting, !stoppedByApp, reconnectFailure == nil,
            let failure = Self.failure(in: line).map({ refined($0, line: line) }).flatMap(Self.reportedWhenReconnecting)
        {
            reconnectFailure = failure
        }
        return nil
    }

    /// A certificate the system trusts but the client does not is not a sign of interception.
    private func refined(_ failure: SessionFailure, line: String) -> SessionFailure {
        failure == .untrustedCertificate && gatewayTrustedBySystem && line.contains("certificate not trusted")
            ? .gatewayCertificateNotPublic : failure
    }

    /// Failures of a reconnection worth telling apart from a lost connection: the user has to act.
    static func reportedWhenReconnecting(_ failure: SessionFailure) -> SessionFailure? {
        switch failure {
        case .wrongPIN, .cardLocked, .cardRefusedLogin, .noCertificate, .multipleCertificates, .untrustedCertificate,
            .gatewayCertificateNotPublic, .gatewayCertificateChanged, .gatewayDenied:
            failure
        default:
            nil
        }
    }

    /// Windows' reasons for ending a session ([MS-RDPBCGR] 2.2.5.1.1). An unknown code is an error
    /// unless the user closed the window (that logs a cancel and wins).
    static func serverEnd(_ code: String) -> SessionEnd? {
        switch code {
        case "ERRINFO_SUCCESS": nil
        // Signed out or disconnected in Windows (Start menu, logoff, tsdiscon).
        case "ERRINFO_LOGOFF_BY_USER", "ERRINFO_RPC_INITIATED_DISCONNECT_BY_USER": .closedByUser
        case "ERRINFO_DISCONNECTED_BY_OTHER_CONNECTION": .failed(.sessionTakenOver)
        case "ERRINFO_IDLE_TIMEOUT": .failed(.idleTimeout)
        // LOGON_TIMEOUT: the limit for an active session elapsed, not inactivity.
        case "ERRINFO_RPC_INITIATED_DISCONNECT", "ERRINFO_RPC_INITIATED_LOGOFF", "ERRINFO_LOGON_TIMEOUT":
            .failed(.disconnectedByServer)
        default: .failed(.other(code))
        }
    }

    /// Error texts in the order they are checked; the first match wins.
    private static let knownFailures: [(text: String, failure: SessionFailure)] = [
        ("no suitable smartcard certificates", .noCertificate),
        ("WRONG PIN", .wrongPIN),
        // The card refused the sign-in with another code: the PIN is never offered again (patch 0001).
        ("- not retrying", .cardRefusedLogin),
        ("certificate not trusted", .untrustedCertificate),
        ("RD Gateway certificate changed", .gatewayCertificateChanged),
        ("inner TLS certificate differs", .untrustedCertificate),
        ("more than one suitable smartcard certificate", .multipleCertificates),
        ("PIN is LOCKED", .cardLocked),
        ("client certificate has no RSA key", .unsupportedCardKey),
        ("ERRCONNECT_DNS_NAME_NOT_FOUND", .gatewayUnreachable),
        ("ERRCONNECT_CONNECT_FAILED", .gatewayUnreachable),
        ("ERRCONNECT_ACCESS_DENIED", .gatewayDenied),
        ("ERRCONNECT_AUTHENTICATION_FAILED", .gatewayDenied),
        ("ERRCONNECT_CONNECT_TRANSPORT_FAILED", .computerUnreachable),
        ("ERRCONNECT_HYBRID_REQUIRED_BY_SERVER", .securityRefused),
    ]

    static func failure(in line: String) -> SessionFailure? {
        guard line.contains("[ERROR]"), !line.contains("ERRCONNECT_CONNECT_CANCELLED") else { return nil }
        if let known = knownFailures.first(where: { line.contains($0.text) }) { return known.failure }
        if let range = line.range(of: #"ERRCONNECT_[A-Z_]+"#, options: .regularExpression) {
            return .other(String(line[range]))
        }
        return nil
    }
}
