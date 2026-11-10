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
    /// Any other error; carries FreeRDP's error name (e.g. `ERRCONNECT_CONNECT_TRANSPORT_FAILED`).
    case other(String)
}

/// Turns FreeRDP log lines into session phases. Feed lines in order; the parser keeps state
/// because the meaning of some lines depends on what happened before.
public struct SessionLogParser: Sendable {
    public private(set) var phase: SessionPhase = .starting
    private var failure: SessionFailure?

    public init() {}

    /// Processes one log line and returns the new phase if it changed.
    @discardableResult
    public mutating func consume(_ line: String) -> SessionPhase? {
        guard let next = nextPhase(for: line), next != phase else { return nil }
        if case .ended = phase { return nil }  // terminal
        phase = next
        return next
    }

    /// Called when the client process exited.
    public mutating func processExited(status: Int32) -> SessionPhase {
        if case .ended = phase { return phase }
        if let failure {
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
        if let failure = Self.failure(in: line) {
            self.failure = self.failure ?? failure
            return nil
        }
        if line.contains("ERRCONNECT_CONNECT_CANCELLED") || line.contains("Network disconnect!") {
            return phase == .connected ? .ended(.closedByUser) : nil
        }
        return nil
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
