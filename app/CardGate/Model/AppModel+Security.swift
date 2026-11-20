import CardGateKit
import Foundation
import OSLog

// MARK: - Connection security

extension AppModel {
    /// The root CA above the card certificate for Kerberos (PKINIT), kept once found. One not found
    /// is looked up again only after the network changed or the computer required NLA (each lookup
    /// may take 10 s, e.g. where the download is reachable only on the organization's network).
    func pkinitAnchor(for certificate: CardCertificate) async -> Data? {
        if let known = securityMemory.anchor(forCertificate: certificate.sha1) { return known }
        if pkinitLookupFailed.contains(certificate.sha1) { return nil }
        guard let der = certificate.der, let root = await PKINITAnchor.root(of: der) else {
            logger.info("No root certification authority found for the card certificate")
            pkinitLookupFailed.insert(certificate.sha1)
            return nil
        }
        securityMemory.rememberAnchor(root, forCertificate: certificate.sha1)
        return root
    }

    /// Kerberos for NLA and the security the connection is made with (`nil`: NLA needed, not possible).
    func connectionSecurity(for profile: ConnectionProfile, certificate: CardCertificate) async
        -> (KerberosSetup, SecurityPlan?)
    {
        let now = Date()
        let remembered = securityMemory.remembered(for: profile)
        let nlaFailed = securityMemory.nlaRecentlyFailed(for: profile, at: now)
        // Not for a computer without a domain or without a gateway: NLA cannot work there anyway.
        let needsKerberos = SecurityPlan.needsKerberos(
            profile.security, remembered: remembered, nlaFailed: nlaFailed,
            nlaPossible: profile.gateway != nil && kerberosRealm(of: profile.computer) != nil, at: now)
        let kerberos = KerberosSetup(
            plugins: FreeRDPCommand.kerberosPlugins(in: Bundle.main.bundleURL), computer: profile.computer,
            gateway: profile.gateway, anchor: needsKerberos ? await pkinitAnchor(for: certificate) : nil)
        let state: SecurityPlan.Kerberos =
            if !needsKerberos { .notNeeded } else if kerberos.isUsable { .ready } else if kerberos.waitsForAnchor {
                .missingAnchor
            } else { .impossible }
        let security = SecurityPlan.make(
            profile.security, remembered: remembered, nlaFailed: nlaFailed, kerberos: state, at: now)
        return (kerberos, security)
    }

    /// Automatic security remembers what the computer chose (see `SecurityPlan`).
    func rememberNegotiatedSecurity() {
        guard let lastAttempt, lastAttempt.security.remembersOutcome, let method = session.negotiatedSecurity else {
            return
        }
        logger.info("Connection security negotiated: \(method.rawValue, privacy: .public)")
        securityMemory.remember(lastAttempt.security.remembering(method, at: Date()), for: lastAttempt.profile)
    }

    /// What is remembered after a failed connection (`SecurityPlan.outcome`); a weaker method only
    /// when the user confirms it (`connectWithWeakerSecurity`), never unnoticed.
    func securityOutcome(_ end: SessionEnd) {
        guard let lastAttempt, case .failed(let failure) = end else { return }
        // The computer requires NLA: look for the root CA again at once.
        if lastAttempt.security.requiresNLAWithoutAnchor(after: failure) { pkinitLookupFailed = [] }
        switch lastAttempt.security.outcome(of: failure) {
        case .keep:
            break
        case .letComputerChooseAgain:
            logger.info("Computer chooses the connection security again after \(String(describing: failure))")
            securityMemory.letComputerChooseAgain(for: lastAttempt.profile)
        case .rememberNLAFailed:
            logger.info("NLA failed with automatic security: the next attempts go without it")
            securityMemory.rememberNLAFailed(for: lastAttempt.profile, at: Date())
        }
    }

    /// The last attempt is the selected connection, unchanged (an action on its failure is meant for it).
    private var lastAttemptIsSelected: Bool {
        guard let lastAttempt, let selected = selectedProfile else { return false }
        return lastAttempt.profile.id == selected.id && lastAttempt.profile.computer == selected.computer
    }

    /// The failure of the last attempt, when it is the selected connection.
    private var selectedFailure: SessionFailure? {
        guard lastAttemptIsSelected, case .ended(.failed(let failure)) = session.phase else { return nil }
        return failure
    }

    /// Automatic security failed with NLA and connects without it next time (the failure says so).
    var connectsWithoutNLANextTime: Bool {
        guard let lastAttempt, let failure = selectedFailure else { return false }
        return lastAttempt.security.outcome(of: failure) == .rememberNLAFailed
    }

    /// The computer requires NLA, which failed before and was not offered (`SecurityPlan.requiresWithheldNLA`).
    var requiresFailedNLA: Bool {
        guard let lastAttempt, let failure = selectedFailure else { return false }
        return lastAttempt.security.requiresWithheldNLA(after: failure)
    }

    /// The computer was not reached with the remembered RDP security; it may require stronger now.
    var computerMayRequireStrongerSecurity: Bool {
        guard let lastAttempt, let failure = selectedFailure else { return false }
        return lastAttempt.security.mayRequireStrongerSecurity(after: failure)
    }

    /// The computer requires NLA and the root CA of the card was not found.
    var requiresNLAWithoutAnchor: Bool {
        guard let lastAttempt, let failure = selectedFailure else { return false }
        return lastAttempt.security.requiresNLAWithoutAnchor(after: failure)
    }

    /// The user wants to try NLA again.
    func tryNLAAgain() {
        guard requiresFailedNLA, let lastAttempt else { return }
        logger.info("NLA tried again by the user")
        securityMemory.forgetNLAFailed(for: lastAttempt.profile)
        connect()
    }

    /// The computer's certificate changed and the user may trust the new one (same connection).
    var canTrustNewComputerCertificate: Bool {
        lastAttemptIsSelected && session.phase == .ended(.failed(.computerCertificateChanged))
            && session.changedCertificateFingerprint != nil
    }

    /// The computer used to accept TLS or NLA and now offers only weaker security
    /// (`SecurityPlan.isWeakened`).
    var securityWeakened: Bool {
        guard let lastAttempt, let failure = selectedFailure else { return false }
        return lastAttempt.security.isWeakened(by: failure)
    }

    /// The user confirmed that the computer's weaker security is intended: it is remembered (no
    /// round of methods the computer refuses), or, if the client did not say which, it chooses again.
    func connectWithWeakerSecurity() {
        guard securityWeakened, let lastAttempt else { return }
        logger.info("Weaker connection security accepted by the user")
        securityMemory.forget(for: lastAttempt.profile)
        if let offered = session.computerOffers {
            securityMemory.remember(RememberedSecurity(method: offered, date: Date()), for: lastAttempt.profile)
        }
        connect()
    }

    /// The user trusts the computer's new certificate (after `computerCertificateChanged`).
    func trustNewComputerCertificate() {
        guard canTrustNewComputerCertificate, let fingerprint = session.changedCertificateFingerprint else { return }
        logger.info("New computer certificate accepted by the user")
        // Only the certificate the user was shown replaces the trusted one, not any that comes next.
        connect(confirmingCertificate: fingerprint)
    }
}

extension AppModel {
    /// The method automatic security uses now for the saved profile `id` (shown in its settings);
    /// `nil` when the computer chooses again (the remembered method stays the weakest allowed).
    func rememberedSecurity(for id: UUID) -> SecurityMethod? {
        guard let profile = profiles.first(where: { $0.id == id }),
            let remembered = securityMemory.remembered(for: profile), remembered.isCurrent(at: Date())
        else { return nil }
        return remembered.method
    }
}

extension SecurityMethod {
    /// Short name in the settings: "Automatic (NLA)".
    var shortName: String {
        switch self {
        case .nla: "NLA"
        case .tls: "TLS"
        case .rdp: String(localized: "RDP Security")
        }
    }
}
