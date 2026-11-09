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
        #expect(parser.consume(Log.networkDisconnect) == .ended(.closedByUser))
        #expect(parser.processExited(status: 0) == .ended(.closedByUser))
    }

    @Test func closingTheWindowAfterConnectIsNotAnError() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.cancelled)
        #expect(parser.phase == .ended(.closedByUser))
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

    @Test func computerUnreachableAfterGateway() {
        var parser = SessionLogParser()
        parser.consume(Log.cardReady)
        parser.consume(Log.gatewayDone)
        parser.consume(Log.transportFailed)
        #expect(parser.processExited(status: 13) == .ended(.failed(.computerUnreachable)))
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
        parser.consume(Log.networkDisconnect)
        #expect(parser.consume(Log.cardReady) == nil)
        #expect(parser.processExited(status: 1) == .ended(.closedByUser))
    }

    @Test func errorLinesWithoutErrorLevelAreIgnored() {
        var parser = SessionLogParser()
        parser.consume(Log.line("WARN", "x", "no suitable smartcard certificates were found"))
        #expect(parser.processExited(status: 0) == .ended(.closedByUser))
    }
}
