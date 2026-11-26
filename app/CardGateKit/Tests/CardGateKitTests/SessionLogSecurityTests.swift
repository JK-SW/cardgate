import CardGateKit
import Testing

/// What the log says about the security of the connection to the computer (TLS, NLA).
struct SessionLogSecurityTests {
    /// A parser past the gateway sign-in: what follows is the computer's.
    func afterGateway() -> SessionLogParser {
        var parser = SessionLogParser()
        parser.consume(Log.cardReady)
        parser.consume(Log.gatewayDone)
        return parser
    }

    static func nego(_ protocolName: String, _ code: String) -> String {
        Log.line("DEBUG", "com.freerdp.core.nego", "[nego_connect]: Negotiated [\(protocolName)][\(code)] security")
    }

    static let negoFailed = Log.line(
        "ERROR", "com.freerdp.core", "[rdp_client_connect]: ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED [0x0002000C]")
    static let accessDenied = Log.line(
        "ERROR", "com.freerdp.core", "[nla_recv_pdu]: ERRCONNECT_ACCESS_DENIED [0x00020016]")
    static let authenticationFailed = Log.line(
        "ERROR", "com.freerdp.core", "[transport_connect_nla]: ERRCONNECT_AUTHENTICATION_FAILED [0x00020009]")

    /// A connection limited to TLS or NLA to a computer that accepts only RDP security.
    @Test func computerOfferingOnlyRDPSecurity() {
        var parser = afterGateway()
        parser.consume(
            Log.line(
                "WARN", "com.freerdp.core.nego",
                "[nego_process_negotiation_failure]: Error: SSL_NOT_ALLOWED_BY_SERVER [0x00000002]"))
        parser.consume(Self.negoFailed)
        #expect(parser.processExited(status: 1) == .ended(.failed(.computerOffersOnlyWeakerSecurity)))
        #expect(parser.computerOffers == .rdp)

        // RDP security was offered too: the client fell back to it itself, and that failed.
        var fallback = SessionLogParser()
        fallback.consume(Self.offered("RDP", true))
        fallback.consume(Self.offered("TLS", true))
        fallback.consume(Log.cardReady)
        fallback.consume(Log.gatewayDone)
        fallback.consume(
            Log.line(
                "WARN", "com.freerdp.core.nego",
                "[nego_process_negotiation_failure]: Error: SSL_NOT_ALLOWED_BY_SERVER [0x00000002]"))
        fallback.consume(Self.negoFailed)
        #expect(fallback.processExited(status: 1) == .ended(.failed(.computerUnreachable)))
    }

    static func offered(_ name: String, _ enabled: Bool) -> String {
        Log.line(
            "DEBUG", "com.freerdp.core.nego",
            "[nego_enable_\(name.lowercased())]: Enabling \(name) security: \(enabled ? "TRUE" : "FALSE")")
    }

    static let sslRequired = Log.line(
        "WARN", "com.freerdp.core.nego",
        "[nego_process_negotiation_failure]: Error: SSL_REQUIRED_BY_SERVER [0x00000001]")

    static func selected(_ name: String, _ code: String) -> String {
        Log.line("DEBUG", "com.freerdp.core.nego", "[nego_recv]: selected_protocol: [\(name)][\(code)]")
    }

    /// Only NLA offered, the computer accepts TLS without it: it selects TLS (no failure is sent),
    /// the client gives up. Weaker security, not an unreachable computer.
    @Test func computerSelectingWeakerSecurity() {
        var nla = SessionLogParser()
        nla.consume(Self.offered("RDP", false))
        nla.consume(Self.offered("TLS", false))
        nla.consume(Self.offered("NLA", true))
        nla.consume(Log.cardReady)
        nla.consume(Log.gatewayDone)
        nla.consume(Self.selected("SSL", "0x00000001"))
        nla.consume(Self.negoFailed)
        #expect(nla.processExited(status: 1) == .ended(.failed(.computerOffersOnlyWeakerSecurity)))
        #expect(nla.computerOffers == .tls)

        // A method that was offered is no refusal.
        var allowed = SessionLogParser()
        allowed.consume(Self.offered("TLS", true))
        allowed.consume(Log.cardReady)
        allowed.consume(Log.gatewayDone)
        allowed.consume(Self.selected("SSL", "0x00000001"))
        allowed.consume(Self.negoFailed)
        #expect(allowed.processExited(status: 1) == .ended(.failed(.computerUnreachable)))
    }

    /// TLS only, the computer requires NLA: it says which (the message names it).
    @Test func computerRequiringNLA() {
        var parser = afterGateway()
        parser.consume(
            Log.line(
                "WARN", "com.freerdp.core.nego",
                "[nego_process_negotiation_failure]: Error: HYBRID_REQUIRED_BY_SERVER [0x00000005]"))
        parser.consume(
            Log.line("ERROR", "com.freerdp.core", "[nego_connect]: ERRCONNECT_HYBRID_REQUIRED_BY_SERVER [0x0002001E]"))
        #expect(parser.processExited(status: 1) == .ended(.failed(.securityRefused)))
        #expect(parser.computerRequires == .nla)
    }

    /// Only RDP security offered, the computer requires TLS: stronger security.
    @Test func computerRequiringTLS() {

        var rdp = SessionLogParser()
        rdp.consume(Self.offered("TLS", false))
        rdp.consume(Self.offered("NLA", false))
        rdp.consume(Log.cardReady)
        rdp.consume(Log.gatewayDone)
        rdp.consume(Self.sslRequired)
        rdp.consume(Self.negoFailed)
        #expect(rdp.processExited(status: 1) == .ended(.failed(.securityRefused)))
        #expect(rdp.computerRequires == .tls)
    }

    /// The security the computer chose; after a fallback the last one counts.
    @Test func negotiatedSecurity() {
        var parser = SessionLogParser()
        #expect(parser.negotiatedSecurity == nil)
        parser.consume(Self.nego("HYBRID_EX", "0x00000008"))
        #expect(parser.negotiatedSecurity == .nla)
        parser.consume(Self.nego("SSL", "0x00000001"))
        #expect(parser.negotiatedSecurity == .tls)
        parser.consume(Self.nego("RDP", "0x00000000"))
        #expect(parser.negotiatedSecurity == .rdp)
    }

    /// Network level authentication: the account may not sign in to the computer.
    @Test func notAllowedOnComputer() {
        var parser = afterGateway()
        parser.consume(
            Log.line(
                "ERROR", "com.freerdp.core.nla",
                "[nla_recv_pdu]: Early User Auth active: FAILURE authorization result 0x00000005"))
        parser.consume(Self.accessDenied)
        #expect(parser.processExited(status: 1) == .ended(.failed(.notAllowedOnComputer)))

        // Another authorization result: the sign-in failed, the account is not the reason.
        var other = afterGateway()
        other.consume(Self.nego("HYBRID_EX", "0x00000008"))
        other.consume(
            Log.line(
                "ERROR", "com.freerdp.core.nla",
                "[nla_recv_pdu]: Early User Auth active: FAILURE authorization result 0x00000001"))
        other.consume(Self.authenticationFailed)
        #expect(other.processExited(status: 1) == .ended(.failed(.kerberosFailed)))

        // Without the early authorization line a denial with NLA is still the computer's.
        var later = afterGateway()
        later.consume(Self.nego("HYBRID_EX", "0x00000008"))
        later.consume(Self.accessDenied)
        #expect(later.processExited(status: 1) == .ended(.failed(.notAllowedOnComputer)))

        // Without NLA it is the gateway's (e.g. its tunnel or channel step).
        var gateway = afterGateway()
        gateway.consume(Self.nego("RDP", "0x00000000"))
        gateway.consume(Self.accessDenied)
        #expect(gateway.processExited(status: 1) == .ended(.failed(.gatewayDenied)))
    }

    /// Kerberos with the card failed; a known harmless Kerberos error line is not a failure.
    @Test func kerberosFailure() {
        var parser = afterGateway()
        parser.consume(
            Log.line(
                "ERROR", "com.winpr.sspi.Kerberos",
                "[kerberos_QueryContextAttributesCommon]: TODO: QueryContextAttributes implement ulAttribute=0x456"))
        parser.consume(
            Log.line(
                "ERROR", "com.winpr.sspi.Kerberos",
                #"[krb5glue_get_init_creds]: krb5_init_creds_get (Cannot find KDC for realm "X" [-1765328230])"#))
        parser.consume(Self.authenticationFailed)
        #expect(parser.processExited(status: 1) == .ended(.failed(.kerberosFailed)))

        // Authentication failed with NLA without a Kerberos line: still not the gateway.
        var later = afterGateway()
        later.consume(Self.nego("HYBRID", "0x00000002"))
        later.consume(Self.authenticationFailed)
        #expect(later.processExited(status: 1) == .ended(.failed(.kerberosFailed)))

        // A Kerberos error WinPR recovered from (it retries), then the computer refuses the account.
        var recovered = afterGateway()
        recovered.consume(
            Log.line(
                "ERROR", "com.winpr.sspi.Kerberos",
                #"[krb5glue_get_init_creds]: krb5_init_creds_get (Cannot find KDC for realm "X" [-1765328230])"#))
        recovered.consume(Self.nego("HYBRID_EX", "0x00000008"))
        recovered.consume(Self.accessDenied)
        #expect(recovered.processExited(status: 1) == .ended(.failed(.notAllowedOnComputer)))

        // ... or the connection to the computer breaks: not a Kerberos failure (NLA stays on).
        var broken = afterGateway()
        broken.consume(
            Log.line(
                "ERROR", "com.winpr.sspi.Kerberos",
                #"[krb5glue_get_init_creds]: krb5_init_creds_get (Cannot find KDC for realm "X" [-1765328230])"#))
        broken.consume(Self.nego("HYBRID_EX", "0x00000008"))
        broken.consume(Log.transportFailed)
        #expect(broken.processExited(status: 1) == .ended(.failed(.computerUnreachable)))

        // Nothing else logged: the Kerberos error is the cause.
        var only = afterGateway()
        only.consume(
            Log.line(
                "ERROR", "com.winpr.sspi.Kerberos",
                #"[krb5glue_get_init_creds]: krb5_init_creds_get (Cannot find KDC for realm "X" [-1765328230])"#))
        #expect(only.processExited(status: 1) == .ended(.failed(.kerberosFailed)))
    }

    /// A Kerberos error WinPR may recover from, then the user cancels or closes the window while
    /// connecting: not a failure (NLA stays on).
    @Test func kerberosErrorThenCancelled() {
        var cancelled = afterGateway()
        cancelled.consume(
            Log.line(
                "ERROR", "com.winpr.sspi.Kerberos",
                #"[krb5glue_get_init_creds]: krb5_init_creds_get (Cannot find KDC for realm "X" [-1765328230])"#))
        cancelled.consume(Log.cancelled)
        #expect(cancelled.processExited(status: 1) != .ended(.failed(.kerberosFailed)))
        var stopped = afterGateway()
        stopped.consume(
            Log.line(
                "ERROR", "com.winpr.sspi.Kerberos",
                #"[krb5glue_get_init_creds]: krb5_init_creds_get (Cannot find KDC for realm "X" [-1765328230])"#))
        stopped.stopRequested()
        #expect(stopped.processExited(status: 15) == .ended(.closedByUser))
        var closed = afterGateway()
        closed.consume(
            Log.line(
                "ERROR", "com.winpr.sspi.Kerberos",
                #"[krb5glue_get_init_creds]: krb5_init_creds_get (Cannot find KDC for realm "X" [-1765328230])"#))
        #expect(closed.processExited(status: 0) == .ended(.closedByUser))
    }

    /// The computer's certificate changed since it was first trusted (patch 0016).
    @Test func computerCertificateChanged() {
        var parser = afterGateway()
        parser.consume(
            Log.line(
                "ERROR", "com.freerdp.crypto",
                "[tls_verify_certificate]: certificate of pc.corp.example:3389 changed since it was first trusted, "
                    + "denying (new fingerprint \(Self.fingerprint))."))
        parser.consume(Log.line("ERROR", "com.freerdp.crypto", "[tls_connect]: certificate not trusted, aborting."))
        #expect(parser.processExited(status: 1) == .ended(.failed(.computerCertificateChanged)))
        // The computer as the client names it (after a redirection another one than connected to),
        // and the new certificate the user may trust.
        #expect(parser.changedCertificateFingerprint == Self.fingerprint)
        #expect(afterGateway().changedCertificateFingerprint == nil)
    }

    static let fingerprint =
        "ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab:ab"

    @Test func fingerprints() {
        #expect(CertificateFingerprint.isValid(Self.fingerprint))
        #expect(!CertificateFingerprint.isValid(Self.fingerprint.uppercased()))
        #expect(!CertificateFingerprint.isValid(String(Self.fingerprint.dropLast(3))))
        #expect(!CertificateFingerprint.isValid("ab:cd"))
    }

    /// Also when the client reconnects after an outage (not the gateway's certificate).
    @Test func computerCertificateChangedWhenReconnecting() {
        var parser = afterGateway()
        parser.consume(Log.gdiInit)
        parser.consume(Log.networkDisconnect)
        parser.consume(Log.reconnecting(1))
        parser.consume(
            Log.line(
                "ERROR", "com.freerdp.crypto",
                "[tls_verify_certificate]: certificate of pc.corp.example:3389 changed since it was first trusted"))
        parser.consume(Log.line("ERROR", "com.freerdp.crypto", "[tls_connect]: certificate not trusted, aborting."))
        #expect(parser.processExited(status: 1) == .ended(.failed(.computerCertificateChanged)))
        #expect(parser.changedCertificateFingerprint == nil, "an older client does not log it")
    }

    /// Reconnecting with NLA, the computer refuses the account: not the gateway's denial.
    @Test func refusedByTheComputerWhenReconnecting() {
        var parser = afterGateway()
        parser.consume(Log.gdiInit)
        parser.consume(Log.networkDisconnect)
        parser.consume(Log.reconnecting(1))
        parser.consume(Log.gatewayDone)
        parser.consume(Self.nego("HYBRID_EX", "0x00000008"))
        parser.consume(Self.accessDenied)
        parser.consume(Log.cancelled)
        #expect(parser.phase == .ended(.failed(.notAllowedOnComputer)))

        // Before the gateway accepted the card it is still the gateway's.
        var gateway = afterGateway()
        gateway.consume(Log.gdiInit)
        gateway.consume(Log.networkDisconnect)
        gateway.consume(Log.reconnecting(1))
        gateway.consume(Self.accessDenied)
        gateway.consume(Log.cancelled)
        #expect(gateway.phase == .ended(.failed(.gatewayDenied)))
    }

    /// The gateway closed the channel to the computer (it could not reach it, or the computer
    /// dropped the connection): not an unexplained exit status.
    @Test func gatewayClosedTheChannel() {
        var parser = afterGateway()
        parser.consume(
            Log.line("ERROR", "com.freerdp.core", "[rdg_process_close_packet]: E_PROXY_INTERNALERROR [0x800759D8]"))
        #expect(parser.processExited(status: 131) == .ended(.failed(.computerUnreachable)))

        // Before it accepted the sign-in it is the gateway's own error, not a lost connection.
        var signingIn = SessionLogParser()
        signingIn.consume(Log.cardReady)
        signingIn.consume(
            Log.line("ERROR", "com.freerdp.core", "[rdg_process_close_packet]: E_PROXY_INTERNALERROR [0x800759D8]"))
        #expect(signingIn.processExited(status: 131) == .ended(.failed(.other("E_PROXY_INTERNALERROR"))))
    }

    /// RDP security only, the gateway closes the channel right after the request reached the
    /// computer: it refuses RDP security (requires TLS or NLA), it is not unreachable.
    @Test func computerRefusingRDPSecurityThroughTheGateway() {
        var parser = afterGateway()
        parser.consume(
            Log.line(
                "DEBUG", "com.freerdp.core.nego",
                "[nego_send_negotiation_request]: RequestedProtocols: [RDP][0x00000000]"))
        parser.consume(
            Log.line("ERROR", "com.freerdp.core", "[rdg_process_close_packet]: E_PROXY_INTERNALERROR [0x800759D8]"))
        #expect(parser.processExited(status: 131) == .ended(.failed(.securityRefused)))

        // With TLS or NLA requested the computer would have said why: still unreachable.
        var tls = afterGateway()
        tls.consume(
            Log.line(
                "DEBUG", "com.freerdp.core.nego",
                "[nego_send_negotiation_request]: RequestedProtocols: [SSL][0x00000001]"))
        tls.consume(
            Log.line("ERROR", "com.freerdp.core", "[rdg_process_close_packet]: E_PROXY_INTERNALERROR [0x800759D8]"))
        #expect(tls.processExited(status: 131) == .ended(.failed(.computerUnreachable)))
    }

    /// Other gateway errors keep their meaning: its policy is not an unreachable computer.
    @Test func gatewayPolicyIsNotAnUnreachableComputer() {
        var parser = afterGateway()
        parser.consume(
            Log.line("ERROR", "com.freerdp.core", "[rdg_process_tunnel_authorization]: E_PROXY_RAP_ACCESSDENIED"))
        parser.consume(Log.line("ERROR", "com.freerdp.core", "[rdg_connect]: ERRCONNECT_ACCESS_DENIED [0x00020016]"))
        #expect(parser.processExited(status: 1) == .ended(.failed(.computerNotAllowedByGateway)))

        var user = afterGateway()
        user.consume(Log.line("ERROR", "com.freerdp.core", "[rdg_x]: E_PROXY_NAP_ACCESSDENIED [0x800759DA]"))
        #expect(user.processExited(status: 1) == .ended(.failed(.gatewayDenied)))
    }
}
