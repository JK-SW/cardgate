import AppKit
import CardGateKit
import CryptoTokenKit
import OSLog
import Observation
import Security

/// Watches smart cards and tokens through CryptoTokenKit (the middleware's token extension) and
/// lists their sign-in certificates. Insertion and removal are reported by the system, so nothing
/// is polled and the card is never accessed with the PIN.
@MainActor
@Observable
final class CardMonitor {
    /// Certificates with a private key on all inserted cards.
    private(set) var certificates: [CardCertificate] = []

    /// The certificate used to sign in, if a suitable card is inserted.
    var signInCertificate: CardCertificate? { CardCertificate.signInCertificate(in: certificates) }

    /// Called after the set of inserted cards changed.
    var onChange: (() -> Void)?

    private let watcher = TKTokenWatcher()
    private let logger = Logger(subsystem: "io.github.jk-sw.cardgate", category: "card")
    private var observers: [any NSObjectProtocol] = []

    init() {
        watcher.setInsertionHandler { [weak self] tokenID in
            Task { @MainActor in self?.tokenInserted(tokenID) }
        }
        // The middleware may need a moment after wake-up; re-read the cards then.
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            })
        refresh()
    }

    private func tokenInserted(_ tokenID: String) {
        logger.info("Token inserted: \(tokenID, privacy: .public)")
        watcher.addRemovalHandler(
            { [weak self] removed in
                Task { @MainActor in
                    self?.logger.info("Token removed: \(removed, privacy: .public)")
                    self?.refresh()
                }
            }, forTokenID: tokenID)
        refresh()
    }

    /// Re-reads the certificates of all inserted cards.
    func refresh() {
        let found = Self.readCertificates()
        guard found != certificates else { return }
        certificates = found
        onChange?()
    }

    private static func readCertificates() -> [CardCertificate] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrAccessGroup as String: kSecAttrAccessGroupToken,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnRef as String: true,
            kSecReturnAttributes as String: true,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let items = result as? [[String: Any]]
        else { return [] }

        return items.compactMap { item -> CardCertificate? in
            guard let tokenID = item[kSecAttrTokenID as String] as? String,
                let ref = item[kSecValueRef as String],
                CFGetTypeID(ref as CFTypeRef) == SecIdentityGetTypeID()
            else { return nil }
            // swiftlint:disable:next force_cast
            let identity = ref as! SecIdentity
            var certificate: SecCertificate?
            guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess, let certificate else {
                return nil
            }
            let name = SecCertificateCopySubjectSummary(certificate) as String? ?? tokenID
            return CardCertificate(
                tokenID: tokenID, holderName: name, extendedKeyUsages: extendedKeyUsages(of: certificate))
        }
        .sorted { $0.holderName < $1.holderName }
    }

    private static func extendedKeyUsages(of certificate: SecCertificate) -> [Data] {
        let keys = [kSecOIDExtendedKeyUsage] as CFArray
        guard let values = SecCertificateCopyValues(certificate, keys, nil) as? [String: Any],
            let eku = values[kSecOIDExtendedKeyUsage as String] as? [String: Any],
            let usages = eku[kSecPropertyKeyValue as String] as? [Data]
        else { return [] }
        return usages
    }
}
