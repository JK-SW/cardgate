public import Foundation

/// How the connection to the computer is secured (connection settings).
///
/// The computer decides what it accepts (Windows: Remote Desktop security layer and network level
/// authentication). `automatic` offers everything, remembers what the computer chose and uses that
/// from then on; it tries again after `RememberedSecurity.validity`.
public enum ConnectionSecurity: String, Codable, CaseIterable, Sendable {
    case automatic
    /// Network level authentication: Kerberos with the card (via the gateway's KDC proxy) and TLS.
    /// The PIN is entered once; Windows signs in with it.
    case nla
    /// TLS without network level authentication; Windows asks for the PIN.
    case tls
    /// RDP security (RC4 between the gateway and the computer); Windows asks for the PIN.
    case rdp
}

/// The security a connection was made with (from the client log).
public enum SecurityMethod: String, Codable, CaseIterable, Comparable, Sendable {
    case rdp
    case tls
    case nla

    /// Stronger methods compare greater.
    public static func < (lhs: SecurityMethod, rhs: SecurityMethod) -> Bool {
        lhs.strength < rhs.strength
    }

    private var strength: Int {
        switch self {
        case .rdp: 0
        case .tls: 1
        case .nla: 2
        }
    }

    /// The protocol FreeRDP logs as negotiated ("Negotiated [HYBRID_EX][0x00000008] security").
    init?(negotiatedProtocol name: String) {
        switch name {
        case "HYBRID", "HYBRID_EX": self = .nla
        case "SSL": self = .tls
        case "RDP": self = .rdp
        default: return nil
        }
    }

    /// The client argument that allows only this method.
    var clientArgument: String {
        switch self {
        // NLA with or without early user authorization (HYBRID_EX, as Windows prefers it).
        case .nla: "/sec:nla:on,ext:on,tls:off,rdp:off"
        case .tls: "/sec:tls"
        case .rdp: "/sec:rdp"
        }
    }
}

/// What `automatic` found for a profile's computer, and when.
public struct RememberedSecurity: Codable, Equatable, Sendable {
    public var method: SecurityMethod
    /// When the computer chose it (`automatic` without a remembered method).
    public var date: Date

    public init(method: SecurityMethod, date: Date) {
        self.method = method
        self.date = date
    }

    /// After this, `automatic` lets the computer choose again (it may accept a stronger method now).
    public static let validity: TimeInterval = 30 * 24 * 60 * 60

    public func isCurrent(at now: Date) -> Bool {
        date <= now && now.timeIntervalSince(date) < Self.validity
    }
}

/// The security arguments for one connection, and what the app does with its outcome.
public struct SecurityPlan: Equatable, Sendable {
    /// `/sec…` arguments; none lets the computer choose among all methods.
    public var arguments: [String]
    /// The method `automatic` remembered for the computer: never connect with a weaker one unless
    /// the user confirms it. `nil` when nothing is remembered or the user set the method.
    public var floor: SecurityMethod?
    /// The computer chooses (among methods at least as strong as `floor`): what it chose is remembered.
    public var remembersOutcome: Bool
    /// NLA is not offered because it failed with automatic security (`SecurityMemory.rememberNLAFailed`).
    public var withholdsFailedNLA: Bool
    /// NLA is not offered because the card's root CA was not found yet (`KerberosSetup.waitsForAnchor`):
    /// what the computer chooses now is not remembered as its choice, the next attempt offers NLA again.
    public var retriesNLA: Bool

    public init(
        arguments: [String], floor: SecurityMethod? = nil, remembersOutcome: Bool = false,
        withholdsFailedNLA: Bool = false, retriesNLA: Bool = false
    ) {
        self.arguments = arguments
        self.floor = floor
        self.remembersOutcome = remembersOutcome
        self.withholdsFailedNLA = withholdsFailedNLA
        self.retriesNLA = retriesNLA
    }

    /// What is remembered when the computer chose `method` (`remembersOutcome`): the weakest method
    /// allowed from now on, and the computer's choice for `RememberedSecurity.validity` unless NLA
    /// was only not offered for now (`retriesNLA`).
    public func remembering(_ method: SecurityMethod, at now: Date) -> RememberedSecurity {
        RememberedSecurity(method: method, date: retriesNLA && method < .nla ? .distantPast : now)
    }

    /// RDP security only, as CardGate connected before 0.7.
    public static let rdpOnly = SecurityPlan(arguments: [SecurityMethod.rdp.clientArgument])

    /// Kerberos with the card for a connection (`needsKerberos`, then `KerberosSetup`).
    public enum Kerberos: Equatable, Sendable {
        /// NLA is not used for this connection; nothing was looked up.
        case notNeeded
        case ready
        /// Only the card's root CA was not found (yet; `KerberosSetup.waitsForAnchor`).
        case missingAnchor
        /// Not possible (no domain, gateway or Kerberos plugins).
        case impossible
    }

    /// NLA may be used, so Kerberos is needed (the card's root CA is looked up only then).
    /// - Parameters:
    ///   - nlaFailed: NLA failed with automatic security recently (`SecurityMemory.nlaRecentlyFailed`).
    ///   - nlaPossible: the computer has a domain (realm) and the connection a gateway (KDC proxy).
    public static func needsKerberos(
        _ security: ConnectionSecurity, remembered: RememberedSecurity?, nlaFailed: Bool, nlaPossible: Bool = true,
        at now: Date
    ) -> Bool {
        guard nlaPossible || security == .nla else { return false }
        return switch security {
        case .nla: true
        case .tls, .rdp: false
        case .automatic:
            if let remembered, remembered.isCurrent(at: now) || remembered.method == .nla {
                remembered.method == .nla
            } else {
                !nlaFailed
            }
        }
    }

    /// The security for a connection; `nil` when it needs NLA and Kerberos is not possible
    /// (`AppAlert.nlaUnavailable`: it could only fail, or connect weaker than the computer accepts).
    /// - Parameters:
    ///   - kerberos: `.notNeeded` unless `needsKerberos`; otherwise what `KerberosSetup` found.
    public static func make(
        _ security: ConnectionSecurity, remembered: RememberedSecurity?, nlaFailed: Bool, kerberos: Kerberos,
        at now: Date
    ) -> SecurityPlan? {
        let nla = kerberos == .ready
        switch security {
        case .nla:
            return nla ? SecurityPlan(arguments: [SecurityMethod.nla.clientArgument]) : nil
        case .tls:
            return SecurityPlan(arguments: [SecurityMethod.tls.clientArgument])
        case .rdp:
            return SecurityPlan(arguments: [SecurityMethod.rdp.clientArgument])
        case .automatic:
            var plan = automatic(remembered: remembered, nlaFailed: nlaFailed, nla: nla, at: now)
            if plan?.remembersOutcome == true, kerberos == .missingAnchor { plan?.retriesNLA = true }
            return plan
        }
    }

    /// `automatic`: what it remembered, or the computer chooses; `nla`: NLA may be offered.
    private static func automatic(remembered: RememberedSecurity?, nlaFailed: Bool, nla: Bool, at now: Date)
        -> SecurityPlan?
    {
        let floor = remembered?.method
        if floor == .nla, !nla { return nil }
        if let remembered, remembered.isCurrent(at: now) {
            return SecurityPlan(arguments: [remembered.method.clientArgument], floor: remembered.method)
        }
        // The computer chooses again (it may accept a stronger method now), never a weaker one.
        let arguments: [String] =
            switch (floor, nla) {
            case (.nla, _): [SecurityMethod.nla.clientArgument]
            case (.tls, true): ["/sec:rdp:off"]
            case (.tls, false): [SecurityMethod.tls.clientArgument]
            case (_, true): []
            // Without Kerberos the computer could choose NLA and fail.
            case (_, false): ["/sec:nla:off,ext:off"]
            }
        return SecurityPlan(
            arguments: arguments, floor: floor, remembersOutcome: true,
            withholdsFailedNLA: nlaFailed && floor != .nla)
    }

    /// What `SecurityMemory` keeps after the connection failed with `failure`.
    public enum Outcome: Equatable, Sendable {
        case keep
        /// The computer may accept a stronger method now: the next attempt lets it choose among
        /// those at least as strong as `floor` (`SecurityMemory.letComputerChooseAgain`).
        case letComputerChooseAgain
        /// The computer chose NLA and Kerberos failed (e.g. the gateway has no KDC proxy): the
        /// next attempts go without it (`SecurityMemory.rememberNLAFailed`).
        case rememberNLAFailed
    }

    public func outcome(of failure: SessionFailure) -> Outcome {
        if let floor, !remembersOutcome,
            failure == .securityRefused || (floor == .rdp && failure == .computerUnreachable)
        {
            // Limited to the remembered method, the computer now requires a stronger one (with
            // RDP security it cannot say so; the gateway reports it unreachable).
            return .letComputerChooseAgain
        }
        if remembersOutcome, failure.isNLASignInFailure, (floor ?? .rdp) < .nla {
            return .rememberNLAFailed
        }
        return .keep
    }

    /// The computer used to accept TLS or NLA and now offers only RDP security: only the user may
    /// accept that (`SecurityMemory.forget`), it may be an attack on the way to the computer.
    public func isWeakened(by failure: SessionFailure) -> Bool {
        failure == .computerOffersOnlyWeakerSecurity && (floor ?? .rdp) > .rdp
    }

    /// The computer requires NLA, which failed before and was therefore not offered: trying it
    /// again is the user's decision (`SecurityMemory.forgetNLAFailed`), the failure is likely to repeat.
    public func requiresWithheldNLA(after failure: SessionFailure) -> Bool {
        failure == .securityRefused && withholdsFailedNLA
    }

    /// Limited to RDP security, the gateway could not reach the computer: it may be off, or require
    /// stronger security now (with RDP security it cannot say so). The next attempt lets it choose.
    public func mayRequireStrongerSecurity(after failure: SessionFailure) -> Bool {
        failure == .computerUnreachable && outcome(of: failure) == .letComputerChooseAgain
    }

    /// The computer requires NLA, which was not offered because the card's root CA was not found
    /// (`retriesNLA`): the next attempt looks for it again.
    public func requiresNLAWithoutAnchor(after failure: SessionFailure) -> Bool {
        failure == .securityRefused && retriesNLA
    }
}

/// Kerberos realm of a computer: its DNS domain in upper case (`pc.corp.example` → `CORP.EXAMPLE`),
/// as in Active Directory. `nil` for a name without a domain or an IP address.
public func kerberosRealm(of computer: HostAddress) -> String? {
    let labels = computer.host.split(separator: ".")
    // An IPv4 address is all digits; a name needs a domain after its first label.
    guard !computer.isIPv6, labels.count >= 2, computer.host.contains(where: \.isLetter) else { return nil }
    let realm = labels.dropFirst().joined(separator: ".").uppercased()
    // Written into krb5.conf as a section name: only what a DNS domain consists of.
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-")
    return realm.unicodeScalars.allSatisfy(allowed.contains) ? realm : nil
}

extension SessionFailure {
    /// The sign-in to the computer with the card (NLA: Kerberos through the gateway) failed in a way
    /// connecting without NLA avoids: Windows then signs in with the card on its own (its clock, its
    /// way to the domain – also when the computer's DNS suffix is not the realm CardGate derives, or
    /// the account is in another domain). Not for a disabled or locked account or a refused card
    /// certificate: Windows refuses them too, turning NLA off would only weaken the connection.
    public var isNLASignInFailure: Bool {
        switch self {
        case .kerberosFailed, .domainUnreachable, .domainNotTrusted, .clockSkew, .computerUnknownToDomain,
            .accountUnknownToDomain:
            true
        default:
            false
        }
    }
}
