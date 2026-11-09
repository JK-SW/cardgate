public import Foundation

/// A certificate with a private key found on an inserted smart card or token.
public struct CardCertificate: Equatable, Sendable, Identifiable {
    /// CryptoTokenKit token identifier (one per inserted card).
    public let tokenID: String
    /// Human readable subject, usually the holder's name.
    public let holderName: String
    /// DER encoded object identifiers of the extended key usages.
    public let extendedKeyUsages: [Data]

    public var id: String { "\(tokenID)|\(holderName)|\(extendedKeyUsages.hashValue)" }

    public init(tokenID: String, holderName: String, extendedKeyUsages: [Data]) {
        self.tokenID = tokenID
        self.holderName = holderName
        self.extendedKeyUsages = extendedKeyUsages
    }

    /// Microsoft Smart Card Logon, 1.3.6.1.4.1.311.20.2.2
    public static let smartCardLogonOID = Data([0x2B, 0x06, 0x01, 0x04, 0x01, 0x82, 0x37, 0x14, 0x02, 0x02])
    /// TLS Web Client Authentication, 1.3.6.1.5.5.7.3.2
    public static let clientAuthOID = Data([0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x02])

    /// Usable to sign in: the gateway needs client authentication, the computer smart card logon.
    public var canSignIn: Bool {
        extendedKeyUsages.contains(Self.smartCardLogonOID) || extendedKeyUsages.contains(Self.clientAuthOID)
    }

    /// The certificate to show to the user: the first one usable for sign-in.
    public static func signInCertificate(in certificates: [CardCertificate]) -> CardCertificate? {
        certificates.first { $0.extendedKeyUsages.contains(smartCardLogonOID) }
            ?? certificates.first(where: \.canSignIn)
    }
}
