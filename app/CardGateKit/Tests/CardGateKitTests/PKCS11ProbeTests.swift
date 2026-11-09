import CardGateKit
import Testing

struct PKCS11ProbeTests {
    @Test func interpretsProbeResults() {
        #expect(PKCS11CardState(error: 0, tokens: 1, certificates: 2) == .ready(certificates: 2))
        #expect(PKCS11CardState(error: 0, tokens: 0, certificates: 0) == .noToken)
        #expect(PKCS11CardState(error: 0, tokens: 1, certificates: 0) == .noCertificates)
        #expect(PKCS11CardState(error: -1, tokens: 0, certificates: 0) == .moduleNotLoadable)
        #expect(PKCS11CardState(error: 0x30, tokens: 0, certificates: 0) == .failed(code: 0x30))
    }

    @Test(arguments: [
        PKCS11CardState.ready(certificates: 3), .noToken, .noCertificates, .moduleNotLoadable, .failed(code: 5),
    ])
    func roundTripsThroughText(_ state: PKCS11CardState) {
        #expect(PKCS11CardState(encoded: state.encoded) == state)
    }

    @Test func rejectsGarbage() {
        #expect(PKCS11CardState(encoded: "") == nil)
        #expect(PKCS11CardState(encoded: "a b c") == nil)
    }

    @Test func missingModuleIsReported() {
        #expect(PKCS11Probe.probe(module: "/nonexistent/module.dylib") == .moduleNotLoadable)
    }
}
