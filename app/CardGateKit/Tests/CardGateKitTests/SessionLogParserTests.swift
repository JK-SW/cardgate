import CardGateKit
import Testing

/// Log lines in the format of FreeRDP 3 (`[time] [pid:tid] [LEVEL][tag] - [function]: message`).
enum Log {
    static func line(_ level: String, _ tag: String, _ message: String) -> String {
        "[21:54:09:517] [2820:6c1b7001] [\(level)][\(tag)] - \(message)"
    }

    static let cardReady = line(
        "INFO", "com.freerdp.core.gateway.rdg_sc",
        "[rdg_sc_new]: smart card ready for RD Gateway authentication (module /m.dylib, slot 0)")
    static let gatewayDone = line(
        "INFO", "com.freerdp.core.gateway.rdg", "[rdg_process_extauth_sc]: RD Gateway smart card authentication done")
    static let gdiInit = line(
        "INFO", "com.freerdp.gdi", "[gdi_init_ex]: Local framebuffer format  PIXEL_FORMAT_BGRA32")
    static let cancelled = line(
        "ERROR", "com.freerdp.core", "[freerdp_abort_connect_context]: ERRCONNECT_CONNECT_CANCELLED [0x0002000B]")
    static let networkDisconnect = line(
        "INFO", "com.freerdp.client.common", "[client_auto_reconnect_ex]: Network disconnect!")
    static let noCertificate = line(
        "ERROR", "com.freerdp.smartcardlogon", "[smartcard_getCert]: no suitable smartcard certificates were found")
    static let wrongPIN = line(
        "ERROR", "com.freerdp.core.gateway.rdg_sc",
        "[sc_login]: WRONG PIN - not retrying. Check remaining attempts before trying again!")
    static let transportFailed = line(
        "ERROR", "com.freerdp.core",
        "[rdp_client_wait_for_activation]: ERRCONNECT_CONNECT_TRANSPORT_FAILED [0x0002000D]")
    static let promptCancelled = line(
        "INFO", "com.freerdp.client.sdl", "[sdl_authenticate_ex]: Credential prompt cancelled, aborting")
    static let noise = line("WARN", "com.freerdp.codec.nsc.neon", "[nsc_init_neon_int]: TODO: Implement neon")
}

struct SessionLogParserTests {
    @Test func successfulSession() {
        var parser = SessionLogParser()
        #expect(parser.phase == .starting)
        #expect(parser.consume(Log.noise) == nil)
        #expect(parser.consume(Log.cardReady) == .authenticatingGateway)
        #expect(parser.consume(Log.gatewayDone) == .connectingComputer)
        #expect(parser.consume(Log.gdiInit) == .connected)
        #expect(parser.consume(Log.gdiInit) == nil)  // no change
        #expect(parser.consume(Log.cancelled) == .ended(.closedByUser))  // window closed
        #expect(parser.consume(Log.networkDisconnect) == nil)
        #expect(parser.processExited(status: 0) == .ended(.closedByUser))
    }

    @Test func closingTheWindowAfterConnectIsNotAnError() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.cancelled)
        #expect(parser.phase == .ended(.closedByUser))
    }

    /// Real case: network turned off while working.
    @Test func lostConnectionIsReported() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.transportFailed)
        #expect(parser.consume(Log.networkDisconnect) == .ended(.failed(.connectionLost)))
        #expect(parser.processExited(status: 0) == .ended(.failed(.connectionLost)))
    }

    /// Real case: Start → Sign out (and tsdiscon) in Windows; the client exits without more.
    @Test func signingOutInWindowsIsNotAnError() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(
            Log.line(
                "INFO", "com.freerdp.core",
                "[rdp_print_errinfo]: ERRINFO_LOGOFF_BY_USER (0x0000000C):The disconnection was initiated by the user"))
        parser.consume(
            Log.line("ERROR", "com.freerdp.core", "[rdp_set_error_info]: ERRINFO_LOGOFF_BY_USER [0x0001000C]"))
        #expect(parser.processExited(status: 0) == .ended(.closedByUser))
    }

    @Test(arguments: [
        ("ERRINFO_DISCONNECTED_BY_OTHER_CONNECTION", SessionEnd.failed(.sessionTakenOver)),
        ("ERRINFO_IDLE_TIMEOUT", .failed(.idleTimeout)),
        ("ERRINFO_RPC_INITIATED_DISCONNECT", .failed(.disconnectedByServer)),
        ("ERRINFO_RPC_INITIATED_DISCONNECT_BY_USER", .closedByUser),
        ("ERRINFO_LOGON_TIMEOUT", .failed(.disconnectedByServer)),
        ("ERRINFO_SERVER_INSUFFICIENT_PRIVILEGES", .failed(.other("ERRINFO_SERVER_INSUFFICIENT_PRIVILEGES"))),
    ])
    func windowsSaysWhyTheSessionEnded(code: String, end: SessionEnd) {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.line("INFO", "com.freerdp.core", "[rdp_print_errinfo]: \(code) (0x00000005):text"))
        #expect(parser.consume(Log.networkDisconnect) == .ended(end))
    }

    @Test func cancelledPINDialogEndsWithoutError() {
        var parser = SessionLogParser()
        parser.consume(Log.promptCancelled)
        parser.consume(
            Log.line("ERROR", "com.freerdp.core.gateway.rdg", "[rdg_connect]: ERRCONNECT_AUTHENTICATION_FAILED"))
        #expect(parser.processExited(status: 1) == .ended(.closedByUser))
    }

    @Test func missingCertificate() {
        var parser = SessionLogParser()
        parser.consume(Log.noCertificate)
        #expect(parser.processExited(status: 1) == .ended(.failed(.noCertificate)))
    }

    @Test func wrongPINWinsOverLaterErrors() {
        var parser = SessionLogParser()
        parser.consume(Log.cardReady)
        parser.consume(Log.wrongPIN)
        parser.consume(Log.transportFailed)
        #expect(parser.processExited(status: 1) == .ended(.failed(.wrongPIN)))
    }

    @Test func untrustedGatewayCertificate() {
        var parser = SessionLogParser()
        parser.consume(
            Log.line("ERROR", "com.freerdp.crypto", "[tls_verify_certificate]: certificate not trusted, aborting."))
        parser.consume(Log.transportFailed)
        #expect(parser.processExited(status: 1) == .ended(.failed(.untrustedCertificate)))
    }

    @Test func multipleCertificatesAndInnerCertificateMismatch() {
        var parser = SessionLogParser()
        parser.consume(
            Log.line(
                "ERROR", "com.freerdp.smartcardlogon",
                "[smartcard_getCert]: more than one suitable smartcard certificate was found"))
        #expect(parser.processExited(status: 1) == .ended(.failed(.multipleCertificates)))

        var mismatch = SessionLogParser()
        mismatch.consume(
            Log.line(
                "ERROR", "com.freerdp.core.gateway.rdg_sc",
                "[sc_verify_peer]: inner TLS certificate differs from the RD Gateway certificate, aborting"))
        #expect(mismatch.processExited(status: 1) == .ended(.failed(.untrustedCertificate)))
    }

    @Test func computerUnreachableAfterGateway() {
        var parser = SessionLogParser()
        parser.consume(Log.cardReady)
        parser.consume(Log.gatewayDone)
        parser.consume(Log.transportFailed)
        #expect(parser.processExited(status: 13) == .ended(.failed(.computerUnreachable)))
    }

    /// Real case: a computer name that does not exist behind the gateway.
    @Test func computerUnknownToTheGateway() {
        var parser = SessionLogParser()
        parser.consume(Log.cardReady)
        parser.consume(Log.gatewayDone)
        parser.consume(Log.line("ERROR", "com.freerdp.core.nego", "[nego_connect]: Failed to connect"))
        parser.consume(
            Log.line(
                "ERROR", "com.freerdp.core",
                "[rdp_client_connect]: ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED [0x0002000C]"))
        #expect(parser.processExited(status: 1) == .ended(.failed(.computerUnreachable)))
    }

    @Test func unknownErrorKeepsItsName() {
        var parser = SessionLogParser()
        parser.consume(Log.line("ERROR", "com.freerdp.core", "[x]: ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED [0x2]"))
        #expect(parser.processExited(status: 1) == .ended(.failed(.other("ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED"))))
    }

    @Test func unexpectedExitWithoutLog() {
        var parser = SessionLogParser()
        #expect(parser.processExited(status: 6) == .ended(.failed(.other("exit status 6"))))
    }

    @Test func cleanExitBeforeConnect() {
        var parser = SessionLogParser()
        parser.consume(Log.cardReady)
        #expect(parser.processExited(status: 0) == .ended(.closedByUser))
    }

    @Test func endedIsTerminal() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.cancelled)
        #expect(parser.consume(Log.cardReady) == nil)
        #expect(parser.consume(Log.networkDisconnect) == nil)
        #expect(parser.processExited(status: 1) == .ended(.closedByUser))
    }

    @Test func errorLinesWithoutErrorLevelAreIgnored() {
        var parser = SessionLogParser()
        parser.consume(Log.line("WARN", "x", "no suitable smartcard certificates were found"))
        #expect(parser.processExited(status: 0) == .ended(.closedByUser))
    }

    /// Windows refuses the account after the logon screen appeared: the client just exits.
    @Test func unknownInfoCodeIsAnErrorUnlessTheUserClosed() {
        var refused = SessionLogParser()
        refused.consume(Log.gdiInit)
        refused.consume(
            Log.line("ERROR", "com.freerdp.core", "[rdp_set_error_info]: ERRINFO_DECRYPT_FAILED2 [0x00011193]"))
        #expect(refused.processExited(status: 0) == .ended(.failed(.other("ERRINFO_DECRYPT_FAILED2"))))

        var closed = SessionLogParser()
        closed.consume(Log.gdiInit)
        closed.consume(
            Log.line("ERROR", "com.freerdp.core", "[rdp_set_error_info]: ERRINFO_DECRYPT_FAILED2 [0x00011193]"))
        #expect(closed.consume(Log.cancelled) == .ended(.closedByUser))
    }

    /// The computer answers but requires TLS or NLA: it was reached, the name is right.
    @Test func computerRefusingTheSecurityIsNotUnreachable() {
        var parser = SessionLogParser()
        parser.consume(Log.cardReady)
        parser.consume(Log.gatewayDone)
        parser.consume(
            Log.line(
                "ERROR", "com.freerdp.core.nego",
                "[nego_process_negotiation_failure]: Error: SSL_REQUIRED_BY_SERVER [0x00000001]"))
        parser.consume(
            Log.line(
                "ERROR", "com.freerdp.core",
                "[rdp_client_connect]: ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED [0x0002000C]"))
        #expect(parser.processExited(status: 1) == .ended(.failed(.securityRefused)))
    }

    /// An error reported before Disconnect is still shown (a wrong PIN used an attempt).
    @Test func errorBeforeStopIsKept() {
        var parser = SessionLogParser()
        parser.consume(Log.cardReady)
        parser.consume(Log.wrongPIN)
        parser.stopRequested()
        #expect(parser.processExited(status: 15) == .ended(.failed(.wrongPIN)))
    }

    /// An error logged while connecting that did not stop the session is not shown after Disconnect.
    @Test func errorBeforeTheDesktopIsOutdatedOnceConnected() {
        var parser = SessionLogParser()
        parser.consume(Log.cardReady)
        parser.consume(Log.wrongPIN)
        parser.consume(Log.gdiInit)
        parser.stopRequested()
        #expect(parser.processExited(status: 15) == .ended(.closedByUser))

        var exited = SessionLogParser()
        exited.consume(Log.cardReady)
        exited.consume(Log.wrongPIN)
        exited.consume(Log.gdiInit)
        #expect(exited.processExited(status: 0) == .ended(.closedByUser))
    }

    /// Disconnect in the Dock or quitting CardGate ends the client: never an error, however it exits.
    @Test func stopByTheAppIsNeverAnError() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.stopRequested()
        parser.consume(Log.transportFailed)
        #expect(parser.consume(Log.networkDisconnect) == .ended(.closedByUser))

        var starting = SessionLogParser()
        starting.consume(Log.cardReady)
        starting.stopRequested()
        #expect(starting.processExited(status: 15) == .ended(.closedByUser))
    }
}
