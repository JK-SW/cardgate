import CardGateKit
import Foundation
import Testing

struct GatewayCheckTests {
    @Test func classifiesErrors() {
        #expect(GatewayCheckResult(error: nil) == .trusted)
        #expect(GatewayCheckResult(error: URLError(.serverCertificateUntrusted)) == .untrusted)
        #expect(GatewayCheckResult(error: URLError(.serverCertificateHasUnknownRoot)) == .untrusted)
        #expect(GatewayCheckResult(error: URLError(.cannotFindHost)) == .unreachable)
        #expect(GatewayCheckResult(error: URLError(.timedOut)) == .unknown)
        #expect(GatewayCheckResult(error: CocoaError(.fileNoSuchFile)) == .unknown)
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
