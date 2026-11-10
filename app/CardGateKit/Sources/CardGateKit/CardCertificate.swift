public import Foundation

/// A certificate with a private key found on an inserted smart card or token.
public struct CardCertificate: Equatable, Sendable, Identifiable {
    /// CryptoTokenKit token identifier (one per inserted card).
    public let tokenID: String
    /// Human readable subject, usually the holder's name.
    public let holderName: String
    /// SHA-1 fingerprint, lower-case hex (identifies the certificate for the RDP client).
    public let sha1: String
    /// DER encoded object identifiers of the extended key usages.
    public let extendedKeyUsages: [Data]
    public let notBefore: Date?
    public let notAfter: Date?

    public var id: String { sha1 }

    public init(
        tokenID: String, holderName: String, sha1: String, extendedKeyUsages: [Data],
        notBefore: Date? = nil, notAfter: Date? = nil
    ) {
        self.tokenID = tokenID
        self.holderName = holderName
        self.sha1 = sha1.lowercased()
        self.extendedKeyUsages = extendedKeyUsages
        self.notBefore = notBefore
        self.notAfter = notAfter
    }

    /// Microsoft Smart Card Logon, 1.3.6.1.4.1.311.20.2.2
    public static let smartCardLogonOID = Data([0x2B, 0x06, 0x01, 0x04, 0x01, 0x82, 0x37, 0x14, 0x02, 0x02])

    /// The RDP client signs in only with certificates for smart card logon.
    public var isLogon: Bool { extendedKeyUsages.contains(Self.smartCardLogonOID) }

    public func isValid(at date: Date) -> Bool {
        (notBefore.map { $0 <= date } ?? true) && (notAfter.map { date <= $0 } ?? true)
    }

    /// Valid smart card logon certificates, newest (latest expiry) first.
    public static func signInCandidates(in certificates: [CardCertificate], at date: Date) -> [CardCertificate] {
        certificates.filter { $0.isLogon && $0.isValid(at: date) }
            .sorted { ($0.notAfter ?? .distantPast) > ($1.notAfter ?? .distantPast) }
    }

    /// The certificate to sign in with: the preferred one if it is on the card and valid, otherwise
    /// the newest valid logon certificate (after a renewal the old one often stays on the card).
    public static func signInCertificate(
        in certificates: [CardCertificate], preferredSHA1: String? = nil, at date: Date
    ) -> CardCertificate? {
        let candidates = signInCandidates(in: certificates, at: date)
        if let preferred = preferredSHA1?.lowercased(), let match = candidates.first(where: { $0.sha1 == preferred }) {
            return match
        }
        return candidates.first
    }

    /// The card has logon certificates, but none is valid now.
    public static func allLogonCertificatesExpired(_ certificates: [CardCertificate], at date: Date) -> Bool {
        certificates.contains(where: \.isLogon) && signInCandidates(in: certificates, at: date).isEmpty
    }

    /// Whether a string is a SHA-1 fingerprint in hex (safe to pass to the client).
    public static func isFingerprint(_ text: String) -> Bool {
        text.count == 40 && text.allSatisfy(\.isHexDigit)
    }
}
