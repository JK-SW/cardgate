import CPKCS11
import Foundation
import Testing

@testable import CardGateKit

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

struct PKCS11CheckProcessTests {
    @Test func readsTheOutputOfTheCheckProcess() {
        #expect(
            PKCS11ProbeResult(processOutput: "0 1\nExample Reader\n", signal: nil)
                == PKCS11ProbeResult(state: .ready, reader: "Example Reader"))
        #expect(
            PKCS11ProbeResult(processOutput: "", signal: nil)
                == PKCS11ProbeResult(state: .failed(code: PKCS11ProbeResult.unreadableCode)))
    }

    /// A check stopped after the time limit (a hanging card driver) fails instead of waiting forever.
    @Test func stoppedCheckFails() {
        #expect(
            PKCS11ProbeResult(processOutput: "0 1", signal: SIGKILL)
                == PKCS11ProbeResult(state: .failed(code: PKCS11ProbeResult.timedOutCode)))
        // A crash in the card driver is not reported as a timeout.
        #expect(
            PKCS11ProbeResult(processOutput: "", signal: SIGSEGV)
                == PKCS11ProbeResult(state: .failed(code: PKCS11ProbeResult.crashedCode)))
        #expect(PKCS11ProbeResult.checkTimeout == .seconds(15))
    }
}

struct PINPolicyTests {
    /// Several tokens (two cards, or one card with two PINs): no length limits from the first token,
    /// but a warning about attempts of any token is kept; another locked token does not block.
    @Test func severalTokensKeepEveryWarning() throws {
        let countLow = UInt(0x1_0000)
        let finalTry = UInt(0x2_0000)
        let locked = UInt(0x4_0000)
        func policy(tokens: Int, first: UInt = 0, any: UInt, error: Int = 0, matched: Bool = false) -> PINPolicy? {
            var result = cg_card_probe_result()
            result.matched_token = matched ? 1 : 0
            result.error = error
            result.tokens = UInt(tokens)
            result.pin_min_length = 6
            result.pin_max_length = 8
            result.token_flags = first
            result.any_token_flags = any
            return PKCS11Probe.pinPolicy(from: result)
        }
        // The token with the sign-in certificate was found: its own limits and warnings only.
        #expect(
            policy(tokens: 2, first: 0, any: locked | finalTry, matched: true) == PINPolicy(minLength: 6, maxLength: 8))
        #expect(policy(tokens: 2, any: 0) == .unknown)
        #expect(policy(tokens: 2, any: 0)?.lengthsKnown == false)
        #expect(try #require(policy(tokens: 2, any: finalTry)).finalTry)
        #expect(try #require(policy(tokens: 2, any: countLow)).countLow)
        let otherLocked = try #require(policy(tokens: 2, any: locked))
        #expect(!otherLocked.locked)
        #expect(otherLocked.finalTry)
        #expect(otherLocked.accepts("123456"))

        #expect(
            policy(tokens: 1, first: finalTry, any: finalTry) == PINPolicy(minLength: 6, maxLength: 8, finalTry: true))
        #expect(policy(tokens: 1, first: 0, any: 0)?.lengthsKnown == true)
        #expect(policy(tokens: 0, any: 0) == nil)
        #expect(policy(tokens: 1, any: 0, error: 5) == nil)
    }

    @Test func matchesTheSignInCertificate() {
        let der: [UInt8] = Array("abc".utf8)
        der.withUnsafeBytes { bytes in
            #expect(PKCS11Probe.certificate(bytes, hasSHA1: "a9993e364706816aba3e25717850c26c9cd0d89d"))
            #expect(!PKCS11Probe.certificate(bytes, hasSHA1: "0000000000000000000000000000000000000000"))
        }
    }

    /// Implausible limits from the card are replaced and not shown as the card's.
    @Test func fallbackLengthsAreNotClaimed() {
        #expect(!PINPolicy(minLength: 0, maxLength: 0, flags: 0).lengthsKnown)
        #expect(PINPolicy(minLength: 4, maxLength: 8, flags: 0).lengthsKnown)
    }

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
