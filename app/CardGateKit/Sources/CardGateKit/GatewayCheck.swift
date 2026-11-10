public import Foundation

/// Result of checking the gateway's HTTPS endpoint with the system's trust evaluation (keychain,
/// revocation, Apple policy) before the RDP client is started.
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
        switch (error as? URLError)?.code {
        case .serverCertificateUntrusted?, .serverCertificateHasBadDate?, .serverCertificateHasUnknownRoot?,
            .serverCertificateNotYetValid?, .secureConnectionFailed?, .clientCertificateRejected?:
            self = .untrusted
        case .cannotFindHost?, .cannotConnectToHost?, .dnsLookupFailed?, .notConnectedToInternet?,
            .networkConnectionLost?:
            self = .unreachable
        default:
            self = .unknown
        }
    }

    /// URL probed for a gateway (the RD Gateway answers HTTPS on the root path).
    public static func url(for gateway: HostAddress) -> URL? {
        URL(string: "https://\(gateway.description)/")
    }
}
