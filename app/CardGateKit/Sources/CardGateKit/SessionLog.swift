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
    case ended(SessionEnd)
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
    case gatewayUnreachable
    case gatewayDenied
    /// The gateway's TLS certificate is not trusted (possible interception).
    case untrustedCertificate
    /// The card holds more than one certificate usable for sign-in.
    case multipleCertificates
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

    public init() {}

    /// Processes one log line and returns the new phase if it changed.
    @discardableResult
    public mutating func consume(_ line: String) -> SessionPhase? {
        guard var next = nextPhase(for: line) else { return nil }
        if stoppedByApp, case .ended(.failed) = next { next = .ended(.closedByUser) }
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

    /// Called when the client process exited.
    public mutating func processExited(status: Int32) -> SessionPhase {
        if case .ended = phase { return phase }
        // An error logged while connecting is outdated once the desktop was shown.
        let failure = phase == .connected ? nil : failure
        if stoppedByApp {
            phase = failure.map { .ended(.failed($0)) } ?? .ended(.closedByUser)
            return phase
        }
        if phase == .connected, let serverEnd {
            phase = .ended(serverEnd)  // e.g. signed out in Windows: the client just exits
        } else if let failure {
            phase = .ended(.failed(failure))
        } else if phase == .connected || status == 0 {
            phase = .ended(.closedByUser)
        } else {
            phase = .ended(.failed(.other("exit status \(status)")))
        }
        return phase
    }

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
        if phase != .connected, !stoppedByApp, var failure = Self.failure(in: line) {
            // The gateway accepted the sign-in, then the connection to the computer failed. If the
            // computer answered with a negotiation failure it was reached but refuses the security;
            // otherwise the gateway closed the channel without a reason: it could not reach the
            // computer (name mistyped or unknown, computer off or offline – it does not say which).
            if phase == .connectingComputer, failure == .other("ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED") {
                failure = negotiationRefused ? .securityRefused : .computerUnreachable
            }
            self.failure = self.failure ?? failure
            return nil
        }
        if phase == .connected {
            return endOfConnectedSession(line)
        }
        return nil
    }

    /// How a session that reached the desktop ends. Closing the window, Disconnect in the Dock or
    /// quitting log a cancel first; signing out in Windows sends an error info code; a broken
    /// connection logs only the transport error and "Network disconnect!".
    private mutating func endOfConnectedSession(_ line: String) -> SessionPhase? {
        if line.contains("ERRCONNECT_CONNECT_CANCELLED") {
            return .ended(.closedByUser)
        }
        if let range = line.range(of: #"ERRINFO_[A-Z0-9_]+"#, options: .regularExpression) {
            serverEnd = serverEnd ?? Self.serverEnd(String(line[range]))
            return nil
        }
        if line.contains("Network disconnect!") {
            return .ended(serverEnd ?? .failed(.connectionLost))
        }
        return nil
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
        ("certificate not trusted", .untrustedCertificate),
        ("inner TLS certificate differs", .untrustedCertificate),
        ("more than one suitable smartcard certificate", .multipleCertificates),
        ("PIN is LOCKED", .cardLocked),
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
