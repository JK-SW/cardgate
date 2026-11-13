import Foundation
import Security
import Testing

@testable import CardGateKit

struct GatewayCheckTests {
    @Test func classifiesErrors() {
        #expect(GatewayCheckResult(error: nil) == .trusted)
        #expect(GatewayCheckResult(error: URLError(.serverCertificateUntrusted)) == .untrusted)
        #expect(GatewayCheckResult(error: URLError(.serverCertificateHasUnknownRoot)) == .untrusted)
        #expect(GatewayCheckResult(error: URLError(.cannotFindHost)) == .unreachable)
        #expect(GatewayCheckResult(error: URLError(.timedOut)) == .unknown)
        #expect(GatewayCheckResult(error: CocoaError(.fileNoSuchFile)) == .unknown)
    }

    /// Inconclusive outcomes let the client decide instead of blocking a working gateway.
    @Test func inconclusiveErrorsDoNotBlock() {
        // The gateway was reached and closed the connection.
        #expect(GatewayCheckResult(error: URLError(.networkConnectionLost)) == .unknown)
        // TLS negotiation failed (e.g. Apple's TLS requirements), not necessarily the certificate.
        #expect(GatewayCheckResult(error: URLError(.secureConnectionFailed)) == .unknown)
        #expect(
            GatewayCheckResult(
                error: URLError(.secureConnectionFailed, userInfo: ["_kCFStreamErrorCodeKey": Int(errSSLProtocol)]))
                == .unknown)
    }

    /// A generic TLS failure with a certificate reason (e.g. revoked, unknown root) still blocks.
    @Test(arguments: [errSSLXCertChainInvalid, errSSLUnknownRootCert, errSSLCertExpired, errSSLHostNameMismatch])
    func certificateReasonsOfATLSFailureBlock(_ code: OSStatus) {
        let stream = URLError(.secureConnectionFailed, userInfo: ["_kCFStreamErrorCodeKey": Int(code)])
        #expect(GatewayCheckResult(error: stream) == .untrusted)
        let underlying = URLError(
            .secureConnectionFailed,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: Int(code))])
        #expect(GatewayCheckResult(error: underlying) == .untrusted)
        // As CFNetwork reports it: the underlying error is -1200 too and carries the TLS code.
        let nested = URLError(
            .secureConnectionFailed,
            userInfo: [
                NSUnderlyingErrorKey: NSError(
                    domain: kCFErrorDomainCFNetwork as String, code: -1200,
                    userInfo: ["_kCFStreamErrorCodeKey": Int(code)])
            ])
        #expect(GatewayCheckResult(error: nested) == .untrusted)
    }

    @Test func redirectsAreNotFollowed() async throws {
        let url = try #require(URL(string: "https://rdg.example.com/"))
        let target = try #require(URL(string: "https://portal.example.com/"))
        let response = try #require(
            HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: nil, headerFields: ["Location": target.absoluteString]))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let next = await RedirectBlocker().urlSession(
            session, task: session.dataTask(with: url), willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: target))
        #expect(next == nil)
    }

    @Test func probeURL() throws {
        #expect(
            GatewayCheckResult.url(for: try HostAddress(parsing: "rdg.example.com"))?.absoluteString
                == "https://rdg.example.com/")
        #expect(
            GatewayCheckResult.url(for: try HostAddress(parsing: "[2001:db8::1]:8443"))?.absoluteString
                == "https://[2001:db8::1]:8443/")
    }
}
