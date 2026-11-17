import CardGateKit
import Foundation
import Testing

struct CardReadinessTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    func cert(_ sha: Character, expiresIn days: Double) -> CardCertificate {
        CardCertificate(
            tokenID: "t", holderName: "Holder", sha1: String(repeating: sha, count: 40),
            extendedKeyUsages: [CardCertificate.smartCardLogonOID],
            notBefore: now.addingTimeInterval(-400 * day), notAfter: now.addingTimeInterval(days * day))
    }

    func evaluate(
        moduleProblem: ModuleProblem? = nil, hasMiddleware: Bool = true, needsReinsert: Bool = false,
        signIn: CardCertificate? = nil, certificates: [CardCertificate] = [], isReading: Bool = false
    ) -> CardReadiness {
        CardReadiness.evaluate(
            moduleProblem: moduleProblem, hasMiddleware: hasMiddleware,
            cards: InsertedCards(certificates: certificates, isReading: isReading, needsReinsert: needsReinsert),
            signInCertificate: signIn, at: now)
    }

    @Test func aModuleProblemComesFirst() {
        let valid = cert("a", expiresIn: 300)
        let problem = ModuleProblem.needsApproval(path: "/m.dylib", sha256: "00")
        #expect(
            evaluate(moduleProblem: problem, hasMiddleware: false, signIn: valid, certificates: [valid])
                == .moduleProblem(problem))
    }

    @Test func missingSoftwareThenReinsertBeforeTheCertificate() {
        let valid = cert("a", expiresIn: 300)
        #expect(evaluate(hasMiddleware: false, needsReinsert: true, signIn: valid) == .noMiddleware)
        #expect(evaluate(needsReinsert: true, signIn: valid, certificates: [valid]) == .needsReinsert)
    }

    @Test func readyWithAnExpiryWarning() {
        let valid = cert("a", expiresIn: 300)
        #expect(evaluate(signIn: valid, certificates: [valid]) == .ready(valid, expiresInDays: nil))
        let soon = cert("b", expiresIn: 5)
        let days = soon.expiryWarning(at: now)
        #expect(days != nil)
        #expect(evaluate(signIn: soon, certificates: [soon]) == .ready(soon, expiresInDays: days))
    }

    /// A connection set to an older certificate is warned about that one, not the renewed one.
    @Test func theWarningConcernsTheCertificateUsed() {
        let old = cert("a", expiresIn: 3)
        let renewed = cert("b", expiresIn: 300)
        guard
            case .ready(let certificate, let days?, let renewedOnCard) = evaluate(
                signIn: old, certificates: [old, renewed])
        else {
            Issue.record("expected a warning")
            return
        }
        #expect(certificate == old)
        #expect(renewedOnCard)
        #expect(days == old.expiryWarning(at: now))
        #expect(evaluate(signIn: renewed, certificates: [old, renewed]) == .ready(renewed, expiresInDays: nil))
    }

    /// Only one certificate, expiring: IT has to renew it.
    @Test func nothingRenewedOnTheCard() {
        let soon = cert("a", expiresIn: 3)
        guard case .ready(_, .some, let renewedOnCard) = evaluate(signIn: soon, certificates: [soon]) else {
            Issue.record("expected a warning")
            return
        }
        #expect(!renewedOnCard)
    }

    @Test func withoutASignInCertificate() {
        #expect(evaluate(certificates: [cert("a", expiresIn: -3)]) == .expired)
        #expect(evaluate(isReading: true) == .reading)
        #expect(evaluate() == .noCard)
        let signature = CardCertificate(tokenID: "t", holderName: "x", sha1: "", extendedKeyUsages: [])
        #expect(evaluate(certificates: [signature]) == .noSignInCertificate)
    }

    @Test func tones() {
        #expect(CardReadiness.moduleProblem(.invalidSignature(path: "/m")).tone == .error)
        #expect(CardReadiness.moduleProblem(.unreadable(path: "/m")).tone == .error)
        #expect(CardReadiness.moduleProblem(.configuredMissing(path: "/m")).tone == .warning)
        #expect(CardReadiness.ready(cert("a", expiresIn: 300), expiresInDays: nil).tone == .success)
        #expect(CardReadiness.ready(cert("a", expiresIn: 3), expiresInDays: 3).tone == .warning)
        #expect(CardReadiness.reading.tone == .info)
        #expect(CardReadiness.noCard.tone == .neutral)
        #expect(CardReadiness.expired.tone == .warning)
    }
}
