import CardGateKit
import Foundation
import Testing

struct CardCertificateTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400
    let logonOID = CardCertificate.smartCardLogonOID
    let otherOID = Data([0x2B, 0x06, 0x01])

    func cert(_ sha: Character, logon: Bool = true, from start: Double = -400, to end: Double) -> CardCertificate {
        CardCertificate(
            tokenID: "t", holderName: "Holder \(sha)", sha1: String(repeating: sha, count: 40),
            extendedKeyUsages: logon ? [logonOID] : [otherOID],
            notBefore: now.addingTimeInterval(start * day), notAfter: now.addingTimeInterval(end * day))
    }

    @Test func validity() {
        #expect(cert("a", to: 10).isValid(at: now))
        #expect(!cert("a", to: -1).isValid(at: now))
        #expect(!cert("a", from: 1, to: 300).isValid(at: now))
        #expect(CardCertificate(tokenID: "t", holderName: "x", sha1: "", extendedKeyUsages: []).isValid(at: now))
    }

    @Test func picksNewestValidLogonCertificate() {
        let expired = cert("a", to: -5)
        let old = cert("b", to: 20)
        let renewed = cert("c", to: 700)
        let signature = cert("d", logon: false, to: 900)
        let all = [expired, old, signature, renewed]
        #expect(CardCertificate.signInCandidates(in: all, at: now) == [renewed, old])
        #expect(CardCertificate.signInCertificate(in: all, at: now) == renewed)
    }

    @Test func preferredCertificateWinsIfValid() {
        let old = cert("b", to: 20)
        let renewed = cert("c", to: 700)
        let expired = cert("a", to: -5)
        #expect(
            CardCertificate.signInCertificate(in: [old, renewed], preferredSHA1: old.sha1.uppercased(), at: now) == old)
        #expect(
            CardCertificate.signInCertificate(in: [renewed, expired], preferredSHA1: expired.sha1, at: now) == renewed)
        #expect(CardCertificate.signInCertificate(in: [renewed], preferredSHA1: "missing", at: now) == renewed)
    }

    @Test func expiredOnly() {
        #expect(
            CardCertificate.allLogonCertificatesExpired([cert("a", to: -1), cert("d", logon: false, to: 9)], at: now))
        #expect(!CardCertificate.allLogonCertificatesExpired([cert("a", to: -1), cert("b", to: 9)], at: now))
        #expect(!CardCertificate.allLogonCertificatesExpired([cert("d", logon: false, to: 9)], at: now))
        #expect(CardCertificate.signInCertificate(in: [cert("d", logon: false, to: 9)], at: now) == nil)
    }

    @Test func fingerprintFormat() {
        #expect(CardCertificate.isFingerprint(String(repeating: "aF", count: 20)))
        #expect(!CardCertificate.isFingerprint("abc"))
        #expect(!CardCertificate.isFingerprint(String(repeating: "g", count: 40)))
    }

    @Test func expiryWarningUsesNewestCertificate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let soon = cert("a", to: 5)
        let renewed = cert("b", to: 400)
        #expect(CardCertificate.expiryWarning(for: [soon], at: now, calendar: calendar) == 5)
        #expect(CardCertificate.expiryWarning(for: [soon, renewed], at: now, calendar: calendar) == nil)
        #expect(CardCertificate.expiryWarning(for: [cert("c", to: 14)], at: now, calendar: calendar) == nil)
        #expect(CardCertificate.expiryWarning(for: [cert("c", to: 13)], at: now, calendar: calendar) == 13)
        #expect(CardCertificate.expiryWarning(for: [cert("c", to: 0.2)], at: now, calendar: calendar) == 0)
        #expect(
            CardCertificate.expiryWarning(for: [cert("d", logon: false, to: 3)], at: now, calendar: calendar) == nil)
    }
}
