import CardGateKit
import Testing

struct PKCS11ProbeTests {
    @Test func interpretsProbeResults() {
        #expect(PKCS11CardState(error: 0, tokens: 1) == .ready)
        #expect(PKCS11CardState(error: 0, tokens: 0) == .noToken)
        #expect(PKCS11CardState(error: -1, tokens: 0) == .moduleNotLoadable)
        #expect(PKCS11CardState(error: 0x30, tokens: 0) == .failed(code: 0x30))
    }

    @Test(arguments: [PKCS11CardState.ready, .noToken, .moduleNotLoadable, .failed(code: 5)])
    func roundTripsThroughText(_ state: PKCS11CardState) {
        #expect(PKCS11CardState(encoded: state.encoded) == state)
    }

    @Test func rejectsGarbage() {
        #expect(PKCS11CardState(encoded: "") == nil)
        #expect(PKCS11CardState(encoded: "a b") == nil)
        #expect(PKCS11CardState(encoded: "0 1 2") == nil)
    }

    @Test func missingModuleIsReported() {
        #expect(PKCS11Probe.probe(module: "/nonexistent/module.dylib") == PKCS11ProbeResult(state: .moduleNotLoadable))
    }

    @Test func carriesTheReaderOfTheToken() {
        let result = PKCS11ProbeResult(state: .ready, reader: "Example USB Reader 0   ")
        #expect(result.reader == "Example USB Reader 0")
        #expect(PKCS11ProbeResult(encoded: result.encoded) == result)
        #expect(PKCS11ProbeResult(encoded: "0 1") == PKCS11ProbeResult(state: .ready))
        #expect(PKCS11ProbeResult(encoded: "0 1\n") == PKCS11ProbeResult(state: .ready))
        #expect(PKCS11ProbeResult(encoded: "x\nReader") == nil)
        // Only a ready token has a reader; blank or control characters are dropped.
        #expect(PKCS11ProbeResult(state: .noToken, reader: "Reader").reader == nil)
        #expect(PKCS11ProbeResult(state: .ready, reader: "   ").reader == nil)
        #expect(PKCS11ProbeResult(state: .ready, reader: "A\u{7}B").reader == nil)
    }
}

struct PINPolicyTests {
    @Test func readsTokenInfo() {
        let policy = PINPolicy(minLength: 4, maxLength: 8, flags: 0)
        #expect(policy == PINPolicy(minLength: 4, maxLength: 8))
        #expect(PINPolicy(minLength: 4, maxLength: 8, flags: 0x1_0000).countLow)
        #expect(PINPolicy(minLength: 4, maxLength: 8, flags: 0x2_0000).finalTry)
        #expect(PINPolicy(minLength: 4, maxLength: 8, flags: 0x4_0000).locked)
    }

    @Test(arguments: [(UInt(0), UInt(0)), (8, 4), (4, 1000)])
    func implausibleLimitsUseFallback(_ limits: (UInt, UInt)) {
        let policy = PINPolicy(minLength: limits.0, maxLength: limits.1, flags: 0)
        #expect(policy.minLength == PINPolicy.fallbackLengths.lowerBound)
        #expect(policy.maxLength == PINPolicy.fallbackLengths.upperBound)
    }

    @Test func acceptsOnlyPlausiblePINs() {
        let policy = PINPolicy(minLength: 4, maxLength: 8)
        #expect(!policy.accepts(""))
        #expect(!policy.accepts("123"))
        #expect(policy.accepts("1234"))
        #expect(policy.accepts("12345678"))
        #expect(!policy.accepts("123456789"))
        #expect(!PINPolicy(minLength: 4, maxLength: 8, locked: true).accepts("1234"))
    }
}
