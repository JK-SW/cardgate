import AppKit
import CardGateKit
import CryptoKit
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

    /// The certificate to sign in with: the preferred one or the newest valid logon certificate.
    func signInCertificate(preferredSHA1: String?) -> CardCertificate? {
        CardCertificate.signInCertificate(in: certificates, preferredSHA1: preferredSHA1, at: Date())
    }

    /// Called after the set of inserted cards changed.
    var onChange: (() -> Void)?

    /// What the PKCS#11 module (and therefore the RDP client) sees; `nil` until checked.
    private(set) var pkcs11State: PKCS11CardState?
    var isChecking: Bool { checkTask != nil }
    /// Reader holding the token (from the last check), redirected to the remote computer.
    private(set) var tokenReader: String?
    private var checkTask: Task<PKCS11ProbeResult, Never>?
    /// PKCS#11 module to check with; set by the app.
    var module: String? {
        didSet { if oldValue != module { scheduleCheck() } }
    }
    nonisolated static let checkArgument = "--check-card"
    private var checkPending = false
    #if DEBUG
        /// Debug builds only, for screenshots of the documentation: `CARDGATE_DEMO_CARD=<holder>`
        /// shows a ready card of that holder instead of the real ones (never in a release).
        private let demoCardHolder = ProcessInfo.processInfo.environment["CARDGATE_DEMO_CARD"]
    #else
        private let demoCardHolder: String? = nil
    #endif

    private let watcher = TKTokenWatcher()
    private let logger = Logger(subsystem: "io.github.jk-sw.cardgate", category: "card")
    private var observers: [any NSObjectProtocol] = []

    init() {
        if let demoCardHolder {
            certificates = [
                CardCertificate(
                    tokenID: "demo", holderName: demoCardHolder, sha1: String(repeating: "0", count: 40),
                    extendedKeyUsages: [CardCertificate.smartCardLogonOID],
                    notBefore: Date(), notAfter: Date().addingTimeInterval(365 * 24 * 3600))
            ]
            pkcs11State = .ready
            return
        }
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
        guard demoCardHolder == nil else { return }
        let found = Self.readCertificates()
        guard found != certificates else { return }
        certificates = found
        pkcs11State = nil
        tokenReader = nil
        onChange?()
        scheduleCheck()
    }

    /// Checks the card through the PKCS#11 module in a separate process (takes about 2–3 s).
    func scheduleCheck() {
        guard demoCardHolder == nil else { return }
        guard let module, !certificates.isEmpty else {
            pkcs11State = nil
            tokenReader = nil
            return
        }
        guard checkTask == nil else {
            checkPending = true
            return
        }
        let task = Task { await Self.check(module: module) }
        checkTask = task
        Task { [weak self] in
            let result = await task.value
            guard let self else { return }
            let reader = result.reader ?? "-"
            let state = result.state.encoded
            self.logger.info("PKCS#11 check: \(state, privacy: .public), reader \(reader, privacy: .public)")
            self.pkcs11State = result.state
            self.tokenReader = result.reader
            self.checkTask = nil
            if self.checkPending {
                self.checkPending = false
                self.scheduleCheck()
            }
        }
    }

    /// The result of the running check, or the last one; waits if a check is in progress.
    func currentState() async -> PKCS11ProbeResult? {
        if let checkTask { return await checkTask.value }
        return pkcs11State.map { PKCS11ProbeResult(state: $0, reader: tokenReader) }
    }

    nonisolated private static func check(module: String) async -> PKCS11ProbeResult {
        guard let executable = Bundle.main.executableURL else { return PKCS11ProbeResult(state: .moduleNotLoadable) }
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
                continuation.resume(
                    returning: PKCS11ProbeResult(encoded: text) ?? PKCS11ProbeResult(state: .failed(code: -2)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: PKCS11ProbeResult(state: .moduleNotLoadable))
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
            let der = SecCertificateCopyData(certificate) as Data
            let sha1 = Insecure.SHA1.hash(data: der).map { String(format: "%02x", $0) }.joined()
            let values =
                SecCertificateCopyValues(
                    certificate,
                    [kSecOIDExtendedKeyUsage, kSecOIDX509V1ValidityNotBefore, kSecOIDX509V1ValidityNotAfter] as CFArray,
                    nil) as? [String: Any] ?? [:]
            return CardCertificate(
                tokenID: tokenID, holderName: name, sha1: sha1,
                extendedKeyUsages: extendedKeyUsages(in: values),
                notBefore: date(in: values, key: kSecOIDX509V1ValidityNotBefore),
                notAfter: date(in: values, key: kSecOIDX509V1ValidityNotAfter))
        }
        .sorted { $0.holderName < $1.holderName }
    }

    private static func extendedKeyUsages(in values: [String: Any]) -> [Data] {
        guard let eku = values[kSecOIDExtendedKeyUsage as String] as? [String: Any],
            let usages = eku[kSecPropertyKeyValue as String] as? [Data]
        else { return [] }
        return usages
    }

    /// Validity dates are given as seconds since the reference date (CFAbsoluteTime).
    private static func date(in values: [String: Any], key: CFString) -> Date? {
        guard let entry = values[key as String] as? [String: Any],
            let seconds = entry[kSecPropertyKeyValue as String] as? NSNumber
        else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
    }
}
