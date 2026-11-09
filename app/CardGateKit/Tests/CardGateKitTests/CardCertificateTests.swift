import CardGateKit
import Foundation
import Testing

struct CardCertificateTests {
    let signing = CardCertificate(tokenID: "t", holderName: "Signature", extendedKeyUsages: [Data([0x2B, 0x06, 0x01])])
    let client = CardCertificate(
        tokenID: "t", holderName: "Client", extendedKeyUsages: [CardCertificate.clientAuthOID])
    let logon = CardCertificate(
        tokenID: "t", holderName: "Logon",
        extendedKeyUsages: [CardCertificate.clientAuthOID, CardCertificate.smartCardLogonOID])

    @Test func signInUsage() {
        #expect(!signing.canSignIn)
        #expect(client.canSignIn)
        #expect(logon.canSignIn)
    }

    @Test func prefersSmartCardLogon() {
        #expect(CardCertificate.signInCertificate(in: [signing, client, logon]) == logon)
        #expect(CardCertificate.signInCertificate(in: [signing, client]) == client)
        #expect(CardCertificate.signInCertificate(in: [signing]) == nil)
        #expect(CardCertificate.signInCertificate(in: []) == nil)
    }
}
