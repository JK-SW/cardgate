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

    /// What the PKCS#11 module (and therefore the RDP client) sees; `nil` until checked.
    private(set) var pkcs11State: PKCS11CardState?
    private(set) var isChecking = false
    /// PKCS#11 module to check with; set by the app.
    var module: String? {
        didSet { if oldValue != module { scheduleCheck() } }
    }
    nonisolated static let checkArgument = "--check-card"
    private var checkPending = false

    private let watcher = TKTokenWatcher()
    private let logger = Logger(subsystem: "io.github.jk-sw.cardgate", category: "card")
    private var observers: [any NSObjectProtocol] = []

    init() {
        // CryptoTokenKit calls its handlers on an XPC queue: they must not be main actor isolated
        // (Swift would trap), so they are explicitly @Sendable and hop to the main actor.
        watcher.setInsertionHandler { @Sendable [weak self] tokenID in
            Task { @MainActor in self?.tokenInserted(tokenID) }
        }
        // The middleware may need a moment after wake-up; re-read the cards then.
        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
            ) { @Sendable [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                    self?.scheduleCheck()
                }
            })
        refresh()
    }

    private func tokenInserted(_ tokenID: String) {
        logger.info("Token inserted: \(tokenID, privacy: .public)")
        watcher.addRemovalHandler(
            { @Sendable [weak self] removed in
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
        pkcs11State = nil
        onChange?()
        scheduleCheck()
    }

    /// Checks the card through the PKCS#11 module in a separate process (it can take seconds).
    func scheduleCheck() {
        guard let module, !certificates.isEmpty else {
            pkcs11State = nil
            return
        }
        guard !isChecking else {
            checkPending = true
            return
        }
        isChecking = true
        Task { [weak self] in
            let state = await Self.check(module: module)
            guard let self else { return }
            self.logger.info("PKCS#11 check: \(state.encoded, privacy: .public)")
            self.pkcs11State = state
            self.isChecking = false
            if self.checkPending {
                self.checkPending = false
                self.scheduleCheck()
            }
        }
    }

    nonisolated private static func check(module: String) async -> PKCS11CardState {
        guard let executable = Bundle.main.executableURL else { return .moduleNotLoadable }
        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = [checkArgument, module]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { _ in
                let output = pipe.fileHandleForReading.readDataToEndOfFile()
                let text = (String(bytes: output, encoding: .utf8) ?? "").trimmingCharacters(
                    in: .whitespacesAndNewlines)
                continuation.resume(returning: PKCS11CardState(encoded: text) ?? .failed(code: -2))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: .moduleNotLoadable)
            }
        }
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
