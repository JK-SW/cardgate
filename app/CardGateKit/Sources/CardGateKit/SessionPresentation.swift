import Foundation

extension SessionPhase {
    /// The step of a connection attempt the main window shows as in progress: 0 starting the
    /// client, 1 the card's PIN, 2 signing in to the gateway, 3 connecting to the computer; `nil`
    /// outside an attempt.
    /// The client reports the gateway sign-in only after it used the PIN (FreeRDP patch 0001), so
    /// the steps never go back.
    public var connectionStep: Int? {
        switch self {
        case .starting: 0
        case .waitingForPIN: 1
        case .authenticatingGateway: 2
        case .connectingComputer: 3
        case .connected, .reconnecting, .ended: nil
        }
    }
}

extension SessionFailure {
    /// An error when the connection was stopped for safety or the card is locked; otherwise a
    /// warning (trying again or fixing the settings helps).
    public var tone: StatusTone {
        switch self {
        case .cardLocked, .untrustedCertificate, .gatewayCertificateNotPublic, .gatewayCertificateChanged: .error
        default: .warning
        }
    }
}
