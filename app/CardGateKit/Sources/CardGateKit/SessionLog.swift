import Foundation

/// Progress of a connection as reported by the FreeRDP client log.
public enum SessionPhase: Equatable, Sendable {
    case starting
    /// Waiting for the smart card / PIN to authenticate to the gateway.
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
        if let failure = Self.failure(in: line) {
            self.failure = self.failure ?? failure
            return nil
        }
        if line.contains("ERRCONNECT_CONNECT_CANCELLED") || line.contains("Network disconnect!") {
            return phase == .connected ? .ended(.closedByUser) : nil
        }
        return nil
    }

    static func failure(in line: String) -> SessionFailure? {
        guard line.contains("[ERROR]") else { return nil }
        if line.contains("no suitable smartcard certificates") { return .noCertificate }
        if line.contains("WRONG PIN") { return .wrongPIN }
        if line.contains("PIN is LOCKED") { return .cardLocked }
        if line.contains("ERRCONNECT_DNS_NAME_NOT_FOUND") || line.contains("ERRCONNECT_CONNECT_FAILED") {
            return .gatewayUnreachable
        }
        if line.contains("ERRCONNECT_ACCESS_DENIED") || line.contains("ERRCONNECT_AUTHENTICATION_FAILED") {
            return .gatewayDenied
        }
        if line.contains("ERRCONNECT_CONNECT_TRANSPORT_FAILED") { return .computerUnreachable }
        if line.contains("ERRCONNECT_CONNECT_CANCELLED") { return nil }
        if let range = line.range(of: #"ERRCONNECT_[A-Z_]+"#, options: .regularExpression) {
            return .other(String(line[range]))
        }
        return nil
    }
}
