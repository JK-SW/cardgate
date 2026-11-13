public import Foundation
import Security

/// Result of checking the gateway's HTTPS endpoint with the system's trust evaluation (keychain,
/// revocation, Apple policy) before the RDP client is started.
///
/// Only a clear answer blocks the connection. Anything inconclusive (a timeout, a dropped
/// connection, a TLS negotiation the system refuses) lets the client decide with its own checks.
/// This is a deliberate trade-off: an attacker who can delay the request also skips the revocation
/// check, but a slow or unusual gateway is never blocked for nothing. The client trusts only public
/// certification authorities, not the keychain (see `SessionFailure.gatewayCertificateNotPublic`).
public enum GatewayCheckResult: Equatable, Sendable {
    case trusted
    case untrusted
    case unreachable
    /// Inconclusive (e.g. timeout of an overloaded gateway); the RDP client decides.
    case unknown

    /// Classifies the outcome of an HTTPS request: any HTTP response means TLS was trusted.
    public init(error: (any Error)?) {
        guard let error else {
            self = .trusted
            return
        }
        let urlError = error as? URLError
        if urlError?.code == .secureConnectionFailed, Self.isCertificateFailure(urlError) {
            self = .untrusted
            return
        }
        switch urlError?.code {
        case .serverCertificateUntrusted?, .serverCertificateHasBadDate?, .serverCertificateHasUnknownRoot?,
            .serverCertificateNotYetValid?, .clientCertificateRejected?:
            self = .untrusted
        case .cannotFindHost?, .cannotConnectToHost?, .dnsLookupFailed?, .notConnectedToInternet?:
            self = .unreachable
        // `secureConnectionFailed` without a certificate reason (above): TLS negotiation failed (e.g.
        // the gateway does not meet Apple's TLS requirements, which the client does not have).
        // `networkConnectionLost`: the gateway was reached and closed the connection.
        default:
            self = .unknown
        }
    }

    /// TLS errors about the server's certificate (Secure Transport codes in the URL error).
    static let certificateFailures: Set<Int> = Set(
        [
            errSSLXCertChainInvalid, errSSLBadCert, errSSLUnknownRootCert, errSSLNoRootCert, errSSLCertExpired,
            errSSLCertNotYetValid, errSSLHostNameMismatch, errSSLATSCertificateTrustViolation,
            errSSLBadCertificateStatusResponse,
        ].map(Int.init))

    /// A generic TLS failure whose Secure Transport code says the server's certificate was refused.
    /// The code is in the URL error or in its underlying (CFNetwork) error. Codes about an alert from
    /// the server (`errSSLPeer…`) concern a client certificate and are not included.
    static func isCertificateFailure(_ error: URLError?) -> Bool {
        guard let error else { return false }
        let streamCode = "_kCFStreamErrorCodeKey"
        let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError
        let codes = [
            error.userInfo[streamCode] as? Int,
            underlying?.userInfo[streamCode] as? Int,
            underlying?.code,
        ]
        return codes.contains { $0.map(certificateFailures.contains) ?? false }
    }

    /// Checks a gateway: name lookup, connection to its HTTPS port and certificate trust. A gateway
    /// often does not answer ping, so this is what tells whether CardGate can reach it.
    public static func probe(_ url: URL) async -> GatewayCheckResult {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        // A redirect (e.g. to a sign-in portal on another host) is the gateway's answer: following
        // it would blame the gateway for the other host's errors.
        let session = URLSession(configuration: .ephemeral, delegate: RedirectBlocker(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            _ = try await session.data(for: request)
            return GatewayCheckResult(error: nil)
        } catch {
            return GatewayCheckResult(error: error)
        }
    }

    /// URL probed for a gateway (the RD Gateway answers HTTPS on the root path).
    public static func url(for gateway: HostAddress) -> URL? {
        URL(string: "https://\(gateway.description)/")
    }
}

/// Keeps a request from following redirects: the redirect response itself is the result.
final class RedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _: URLSession, task _: URLSessionTask, willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
