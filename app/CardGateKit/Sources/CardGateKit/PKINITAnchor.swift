public import Foundation
import Security

/// The certification authority Kerberos trusts for the domain controller's certificate when it
/// signs in with the card (PKINIT anchor).
///
/// It is the root of the card certificate's own chain: in Active Directory the domain controllers
/// and the users' smart card logon certificates are issued under the same root. macOS builds the
/// chain, downloading missing issuers from the addresses in the certificates (AIA), as when it
/// checks any certificate. The root is used only if the card certificate verifies up to it.
///
/// Downloads (AIA, often plain HTTP) are not authenticated: someone on the way could serve an
/// intermediate with the real issuer's name and key signed by a root of their own, which then
/// verifies too. That root cannot be misused: Kerberos gets the domain controller's certificate
/// only through the gateway's KDC proxy, over HTTPS to the gateway, whose certificate the system
/// checks – nobody else can put a certificate of theirs in that reply.
public enum PKINITAnchor {
    /// The root certificate (DER) above `certificate` (DER), or `nil` if no complete chain is found
    /// within `timeout` (downloads may hang before the network is up; Connect waits for this).
    public static func root(of certificate: Data, timeout: Duration = .seconds(10)) async -> Data? {
        await withTimeout(timeout, fallback: nil) { findRoot(of: certificate) }
    }

    static func findRoot(of der: Data) -> Data? {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData) else { return nil }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
            let trust
        else { return nil }
        SecTrustSetNetworkFetchAllowed(trust, true)
        // Builds the chain; it fails when the root is not trusted on this Mac, the chain is still built.
        _ = SecTrustEvaluateWithError(trust, nil)
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], chain.count >= 2,
            let root = chain.last, isSelfSigned(root),
            verifies(certificate, intermediates: Array(chain.dropFirst().dropLast()), root: root)
        else { return nil }
        return SecCertificateCopyData(root) as Data
    }

    static func isSelfSigned(_ certificate: SecCertificate) -> Bool {
        guard let subject = SecCertificateCopyNormalizedSubjectSequence(certificate),
            let issuer = SecCertificateCopyNormalizedIssuerSequence(certificate)
        else { return false }
        return (subject as Data) == (issuer as Data)
    }

    /// `certificate` verifies (signatures, validity) up to `root` and only to it.
    static func verifies(_ certificate: SecCertificate, intermediates: [SecCertificate], root: SecCertificate) -> Bool {
        var trust: SecTrust?
        guard
            SecTrustCreateWithCertificates(
                ([certificate] + intermediates) as CFArray, SecPolicyCreateBasicX509(), &trust) == errSecSuccess,
            let trust,
            SecTrustSetAnchorCertificates(trust, [root] as CFArray) == errSecSuccess,
            SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
            SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess
        else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }

    /// PEM text of a DER certificate (what Kerberos reads from `pkinit_anchors = FILE:`).
    public static func pem(_ der: Data) -> String {
        let base64 = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN CERTIFICATE-----\n\(base64)\n-----END CERTIFICATE-----\n"
    }
}
