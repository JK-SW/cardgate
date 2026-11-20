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
    /// The computer accepts only weaker security than this connection is limited to (RDP security,
    /// or TLS when limited to NLA).
    case computerOffersOnlyWeakerSecurity
    /// The computer's certificate (TLS) is not the one it had when first connected to: possible
    /// interception, or the computer got a new certificate.
    case computerCertificateChanged
    /// Network level authentication: the account may not sign in to this computer remotely.
    case notAllowedOnComputer
    /// Network level authentication: Kerberos with the card failed (domain controller not reached
    /// through the gateway's KDC proxy, account or computer not found).
    case kerberosFailed
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
    /// The negotiation failure said the computer accepts only weaker security than offered.
    private var onlyWeakerSecurity = false
    /// The weaker method the computer accepts (`computerOffersOnlyWeakerSecurity`): RDP security,
    /// or the one it selected although it was not offered.
    public private(set) var computerOffers: SecurityMethod?
    /// The stronger method the computer requires (`securityRefused`): NLA or TLS, if it said which.
    public private(set) var computerRequires: SecurityMethod?
    /// What the client offered the computer ("Enabling TLS security: TRUE").
    private var offered: Set<SecurityMethod> = []
    /// The client sent the computer a request for RDP security only ("RequestedProtocols: [RDP]"):
    /// the gateway had reached it.
    private var requestedOnlyRDP = false
    /// A Kerberos call failed; WinPR may have recovered from it (it retries), so it is the cause
    /// only when nothing else explains the failure.
    private var kerberosError = false
    /// While reconnecting: the gateway accepted the card again, what follows is the computer's.
    private var reconnectPastGateway = false
    /// The security the client last negotiated with the computer.
    public private(set) var negotiatedSecurity: SecurityMethod?
    /// The computer certificate that changed since it was first trusted (`CertificateFingerprint`);
    /// trusting it passes it back (`FreeRDPCommand.confirmedCertificateVariable`), so only this
    /// certificate is accepted. `nil` also when the client did not log it.
    public private(set) var changedCertificateFingerprint: String?
    /// The user cancelled while connecting (or CardGate stopped the client): no Kerberos fallback.
    private var cancelled = false
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
        } else if kerberosError, !phase.hasDesktop, !cancelled, !crashed, status != 0 {
            // Nothing else explains why the client gave up (a Kerberos error may be recovered from).
            phase = .ended(.failed(.kerberosFailed))
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
        noteNegotiation(line)
        if noteCancelOrKerberosError(line) { return nil }
        if !stoppedByApp, var failure = Self.failure(in: line) {
            // The gateway accepted the sign-in, then the connection to the computer failed. If the
            // computer answered with a negotiation failure it was reached but refuses the security;
            // otherwise the gateway closed the channel without a reason: it could not reach the
            // computer (name mistyped or unknown, computer off or offline – it does not say which).
            if phase == .connectingComputer { failure = computerFailure(failure, line: line) }
            // A broken transport (the only source of `computerUnreachable` in the table) is the
            // computer's only after the gateway accepted the sign-in. Before the PIN was asked for,
            // the connection to the gateway could not be set up (e.g. TLS); after, it broke.
            if failure == .computerUnreachable, phase != .connectingComputer {
                if let code = Self.gatewayProxyCodes.first(where: line.contains) {
                    failure = .other(code)  // an error of the gateway itself, while signing in
                } else {
                    failure = phase == .starting && !pinRequested ? .gatewayUnreachable : .connectionLost
                }
            }
            self.failure = self.failure ?? refined(failure, line: line)  // the first failure is the cause
            return nil
        }
        return nil
    }

    /// Notes a cancel and a Kerberos error (only a possible cause, see `kerberosError`); true for the latter.
    private mutating func noteCancelOrKerberosError(_ line: String) -> Bool {
        if line.contains("ERRCONNECT_CONNECT_CANCELLED") { cancelled = true }
        guard Self.isKerberosError(line) else { return false }
        kerberosError = true
        return true
    }

    /// What the computer said while the security was negotiated.
    private mutating func noteNegotiation(_ line: String) {
        if line.contains("[nego_enable_") {
            for (name, method) in [("RDP", SecurityMethod.rdp), ("TLS", .tls), ("NLA", .nla)]
            where line.contains("Enabling \(name) security: ") {
                if line.contains("security: TRUE") { offered.insert(method) } else { offered.remove(method) }
            }
        }
        if line.contains("RequestedProtocols: ") { requestedOnlyRDP = line.contains("RequestedProtocols: [RDP]") }
        if line.contains("nego_process_negotiation_failure") {
            negotiationRefused = true
            // The computer accepts only RDP security; the other failures ask for stronger security.
            if line.contains("SSL_NOT_ALLOWED_BY_SERVER") {
                onlyWeakerSecurity = true
                computerOffers = .rdp
            } else if line.contains("HYBRID_REQUIRED_BY_SERVER") || line.contains("SSL_WITH_USER_AUTH_REQUIRED") {
                computerRequires = .nla
            } else if line.contains("SSL_REQUIRED_BY_SERVER") {
                computerRequires = .tls
            }
        }
        // The computer chose a method the client did not offer (it does not send a failure then):
        // a weaker one, e.g. TLS when only NLA was offered.
        if line.contains("selected_protocol: ["),
            let range = line.range(of: #"selected_protocol: \[[A-Z_]+\]"#, options: .regularExpression),
            let method = SecurityMethod(
                negotiatedProtocol: String(line[range].dropFirst("selected_protocol: [".count).dropLast())),
            !offered.isEmpty, !offered.contains(method)
        {
            negotiationRefused = true
            onlyWeakerSecurity = true
            computerOffers = method
        }
        noteChangedCertificate(line)
        if line.contains("Negotiated ["),
            let range = line.range(of: #"Negotiated \[[A-Z_]+\]"#, options: .regularExpression)
        {
            let name = line[range].dropFirst("Negotiated [".count).dropLast()
            negotiatedSecurity = SecurityMethod(negotiatedProtocol: String(name)) ?? negotiatedSecurity
        }
    }

    /// The computer's certificate changed since it was first trusted (patch 0016), also when reconnecting.
    private mutating func noteChangedCertificate(_ line: String) {
        if line.contains("changed since it was first trusted"),
            let found = line.range(of: #"new fingerprint [0-9a-f:]+\)"#, options: .regularExpression)
        {
            let fingerprint = String(line[found].dropFirst("new fingerprint ".count).dropLast())
            changedCertificateFingerprint = CertificateFingerprint.isValid(fingerprint) ? fingerprint : nil
        }
    }

    /// A failure after the gateway accepted the card, told apart by what the computer answered.
    private func computerFailure(_ failure: SessionFailure, line: String) -> SessionFailure {
        switch failure {
        case .other("ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED"):
            // When the client offered RDP security too, it fell back to it itself: that connection failed.
            if onlyWeakerSecurity {
                return offered.contains(.rdp) ? .computerUnreachable : .computerOffersOnlyWeakerSecurity
            }
            return negotiationRefused ? .securityRefused : .computerUnreachable
        case .computerUnreachable where requestedOnlyRDP && Self.gatewayProxyCodes.contains(where: line.contains):
            // The gateway reached the computer and closed the channel right after the request for RDP
            // security: the computer does not accept it (it says nothing else over the gateway). A
            // computer that is off or unknown fails before, when the gateway opens the channel.
            return .securityRefused
        case .gatewayDenied where negotiatedSecurity == .nla || kerberosError:
            // With network level authentication, access denied and failed authentication now are
            // the computer's, not the gateway's.
            return line.contains("ERRCONNECT_ACCESS_DENIED") ? .notAllowedOnComputer : .kerberosFailed
        default:
            return failure
        }
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
            reconnectPastGateway = false
            negotiatedSecurity = nil
            kerberosError = false
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
        if phase == .reconnecting { noteReconnectFailure(line) }
        return nil
    }

    /// The first failure of reconnecting the user has to act on; network errors of the attempts
    /// before do not hide it.
    private mutating func noteReconnectFailure(_ line: String) {
        if line.contains("RD Gateway smart card authentication done") { reconnectPastGateway = true }
        noteNegotiation(line)
        if Self.isKerberosError(line) { kerberosError = true }
        guard !stoppedByApp, reconnectFailure == nil, var failure = Self.failure(in: line) else { return }
        // As when connecting: after the gateway accepted the card, a refusal may be the computer's (NLA).
        if reconnectPastGateway { failure = computerFailure(failure, line: line) }
        reconnectFailure = Self.reportedWhenReconnecting(refined(failure, line: line))
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
            .gatewayCertificateNotPublic, .gatewayCertificateChanged, .gatewayDenied, .computerCertificateChanged,
            .notAllowedOnComputer, .kerberosFailed:
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
}
