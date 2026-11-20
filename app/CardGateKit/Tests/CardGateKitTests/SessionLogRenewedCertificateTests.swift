import CardGateKit
import Testing

/// A renewed certificate of the computer with NLA (patch 0018).
extension SessionLogSecurityTests {
    /// Patch 0018: with NLA a changed certificate waits for Kerberos to verify the computer.
    static let awaitsKerberos = Log.line(
        "WARN", "com.freerdp.crypto",
        "[tls_verify_certificate]: certificate of pc.corp.example:3389 changed since it was first trusted, "
            + "accepted until Kerberos verifies the computer (new fingerprint \(fingerprint)).")

    /// Kerberos verified the computer: the renewed certificate is trusted, nothing to report.
    @Test func renewedCertificateVerifiedByKerberos() {
        var parser = afterGateway()
        parser.consume(Self.nego("HYBRID_EX", "0x00000008"))
        parser.consume(Self.awaitsKerberos)
        parser.consume(
            Log.line(
                "INFO", "com.freerdp.crypto",
                "[freerdp_tls_save_pending_certificate]: changed certificate of pc.corp.example:3389 "
                    + "verified by Kerberos, replacing the stored one."))
        #expect(parser.consume(Log.gdiInit) == .connected)
        #expect(parser.changedCertificateFingerprint == nil)
    }

    /// Also when the verified certificate cannot be stored: the computer is verified.
    @Test func renewedCertificateVerifiedNotStored() {
        var parser = afterGateway()
        parser.consume(Self.awaitsKerberos)
        parser.consume(
            Log.line(
                "WARN", "com.freerdp.crypto",
                "[freerdp_tls_save_pending_certificate]: changed certificate of pc.corp.example:3389 "
                    + "verified by Kerberos, unable to store it."))
        #expect(parser.consume(Log.gdiInit) == .connected)
        #expect(parser.changedCertificateFingerprint == nil)
    }

    /// The client denies a changed certificate Kerberos did not verify: reported with its fingerprint.
    @Test func renewedCertificateNotVerified() {
        var denied = afterGateway()
        denied.consume(Self.nego("HYBRID_EX", "0x00000008"))
        denied.consume(Self.awaitsKerberos)
        denied.consume(
            Log.line(
                "ERROR", "com.freerdp.core.nla",
                "[nla_client_recv_pub_key_auth]: certificate of the computer changed since it was first trusted "
                    + "and Kerberos did not verify the computer, denying."))
        #expect(denied.processExited(status: 1) == .ended(.failed(.computerCertificateChanged)))
        #expect(denied.changedCertificateFingerprint == Self.fingerprint)
    }

    /// Other failures while the certificate awaits Kerberos are reported as they are (the
    /// certificate is not stored; without NLA the client then denies it).
    @Test func otherFailuresWhileCertificateAwaitsKerberos() {
        var refused = afterGateway()
        refused.consume(Self.nego("HYBRID_EX", "0x00000008"))
        refused.consume(Self.awaitsKerberos)
        refused.consume(Self.accessDenied)
        #expect(refused.processExited(status: 1) == .ended(.failed(.notAllowedOnComputer)))

        var wrongPIN = afterGateway()
        wrongPIN.consume(Self.nego("HYBRID_EX", "0x00000008"))
        wrongPIN.consume(Self.awaitsKerberos)
        wrongPIN.consume(Log.wrongPIN)
        #expect(wrongPIN.processExited(status: 1) == .ended(.failed(.wrongPIN)))
    }
}
