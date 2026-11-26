import CPKCS11
import Foundation
import Testing

@testable import CardGateKit

/// The card in the redirected reader and reconnecting without it.
extension ConnectionLogTests {
    /// Windows' work with the card, and the answers the client passes to it, are not the client's problems.
    @Test func redirectedCardLinesAreHarmless() {
        var log = ConnectionLog()
        _ = log.consume(Log.gdiInit)
        let lines = [
            Log.line(
                "WARN", "com.freerdp.utils.smartcard.call",
                "[smartcard_transaction_watchdog]: transaction on hCard 0x0000001b idle for more than 5000 ms, "
                    + "ending it and resetting the card like Windows does"),
            Log.line(
                "ERROR", "com.freerdp.utils.smartcard.call",
                "[scard_log_status_error_wlog]: SCardTransmit failed with error SCARD_W_REMOVED_CARD [-2146434967]"),
            Log.line(
                "ERROR", "com.freerdp.utils.smartcard.call",
                "[scard_log_status_error_wlog]: IRP failure: SCardConnectW (0x000900B0) failed with error "
                    + "SCARD_E_NO_SMARTCARD [-2146435060]"),
        ]
        #expect(lines.map { log.consume($0) } == [.harmless, .harmless, .harmless])
        #expect(log.entries.map(\.event) == [.desktopShown])
        // Other errors of redirecting the card stay errors.
        let failed = Log.line(
            "ERROR", "com.freerdp.utils.smartcard.call", "[smartcard_call_context_new]: Failed to load WinSCard API!")
        #expect(log.consume(failed) == .error)
        let noService = Log.line(
            "ERROR", "com.freerdp.utils.smartcard.call",
            "[scard_log_status_error_wlog]: SCardEstablishContext failed with error SCARD_E_NO_SERVICE [-2146435043]")
        #expect(log.consume(noService) == .error)
    }

    /// Only changes are listed; the card is in the reader when connecting.
    @Test func cardRemovedAndInserted() {
        var log = ConnectionLog()
        log.cardInReader(true)
        log.cardInReader(false)
        log.cardInReader(false)
        log.cardInReader(true)
        #expect(log.entries.map(\.event) == [.cardRemoved, .cardInserted])
        #expect(log.entries.map(\.event.severity) == [.warning, .info])
    }

    /// Why reconnecting failed, as the parser says it: once per outage; the end says it instead.
    @Test func reconnectingWithoutTheCard() {
        var log = ConnectionLog()
        for line in [Log.gdiInit, Log.networkDisconnect, Log.reconnecting(0)] { _ = log.consume(line) }
        log.reconnectFailed(.noCertificate, line: Log.noCertificate)
        _ = log.consume(Log.reconnecting(1))
        log.reconnectFailed(.wrongPIN, line: Log.wrongPIN)
        #expect(
            log.entries.map(\.event) == [
                .desktopShown, .connectionInterrupted, .reconnecting(attempt: 1, total: 10),
                .reconnectFailed(.noCertificate), .reconnecting(attempt: 2, total: 10),
            ])
        #expect(log.entries[3].event.severity == .warning)
        // A card event in between does not keep the duplicate.
        log.cardInReader(true)
        log.cardInReader(false)
        log.note(.ended(.failed(.noCertificate)))
        #expect(
            log.entries.suffix(3).map(\.event) == [
                .reconnecting(attempt: 2, total: 10), .cardRemoved, .ended(.failed(.noCertificate)),
            ])
    }

    /// A new outage lists its own failure; none after the user disconnected.
    @Test func reconnectFailurePerOutage() {
        var log = ConnectionLog()
        for line in [Log.gdiInit, Log.networkDisconnect, Log.reconnecting(0)] { _ = log.consume(line) }
        log.reconnectFailed(.noCertificate, line: Log.noCertificate)
        for line in [Log.reconnected, Log.networkDisconnect, Log.reconnecting(0)] { _ = log.consume(line) }
        log.reconnectFailed(.noCertificate, line: Log.noCertificate)
        #expect(log.entries.filter { $0.event == .reconnectFailed(.noCertificate) }.count == 2)

        var stopped = ConnectionLog()
        for line in [Log.gdiInit, Log.networkDisconnect, Log.reconnecting(0)] { _ = stopped.consume(line) }
        stopped.stopRequested()
        stopped.reconnectFailed(.noCertificate, line: Log.noCertificate)
        #expect(!stopped.entries.contains { $0.event == .reconnectFailed(.noCertificate) })

        // Not without an outage (the parser reports it only while reconnecting).
        var connected = ConnectionLog()
        _ = connected.consume(Log.gdiInit)
        connected.reconnectFailed(.noCertificate, line: Log.noCertificate)
        #expect(connected.entries.map(\.event) == [.desktopShown])
    }
}

/// Failures named in words: their technical lines stay in the detailed log.
extension ConnectionLogTests {
    /// The consequences of a cancelled PIN or a failed connection are not listed.
    @Test func consequencesOfAFailureAreNotListed() {
        var log = ConnectionLog()
        let lines = [
            Log.promptCancelled,
            Log.line(
                "ERROR", "com.freerdp.core",
                "[rdg_get_gateway_credentials]: ERRCONNECT_CONNECT_CANCELLED [0x0002000B]"),
            Log.line("ERROR", "com.freerdp.core.nego", "[nego_connect]: Failed to connect"),
            Log.line(
                "ERROR", "com.freerdp.core.connection",
                "[rdp_client_connect]: Error: protocol security negotiation or connection failure"),
            Log.line("ERROR", "com.freerdp.core.transport", "[transport_layer_bio_ctrl]: Unsupported BIO_CTRL 2"),
            Log.line("ERROR", "com.freerdp.core.transport", "[winpr_log_backtrace_ex]: 0: address=0x1"),
            Log.line(
                "WARN", "com.freerdp.smartcardlogon",
                #"[list_provider_keys]: Key Storage Provider [\\.\Reader\] no certificates found"#),
            Log.line(
                "WARN", "com.freerdp.core.gateway.rdg",
                "[rdg_x]: Unexpected HTTP status: HTTP_STATUS_SERVICE_UNAVAIL [503]"),
        ]
        for line in lines { _ = log.consume(line) }
        #expect(log.entries.isEmpty)
        // Another HTTP status stays listed.
        _ = log.consume(
            Log.line(
                "WARN", "com.freerdp.core.gateway.rdg",
                "[rdg_x]: Unexpected HTTP status: HTTP_STATUS_SERVER_ERROR [500]"))
        #expect(log.entries.count == 1)
    }

    /// The gateway's time limit: the interruption says why.
    @Test func gatewaySessionExpired() {
        var log = ConnectionLog()
        let lines = [
            Log.gdiInit,
            Log.line("ERROR", "com.freerdp.core", "[rdg_process_close_packet]: E_PROXY_SESSIONTIMEOUT [0x800759F6]"),
            Log.transportFailed, Log.networkDisconnect, Log.reconnecting(0), Log.reconnected, Log.networkDisconnect,
        ]
        for line in lines { _ = log.consume(line) }
        #expect(
            log.entries.map(\.event) == [
                .desktopShown, .gatewaySessionExpired, .reconnecting(attempt: 1, total: 10), .reconnected,
                .connectionInterrupted,
            ])
        #expect(log.entries[1].event.severity == .warning)
    }

    /// Sound fails once per session; its lines are not listed.
    @Test func soundFailed() {
        var log = ConnectionLog()
        let failed = Log.line(
            "ERROR", "com.freerdp.channels.rdpsnd.client",
            "[rdpsnd_mac_play]: audio output failed, dropping sound until the device is closed: x")
        for line in [Log.gdiInit, failed, failed] { _ = log.consume(line) }
        #expect(log.entries.map(\.event) == [.desktopShown, .soundFailed])
    }

    /// When Kerberos said why it failed, its lines stay in the detailed log.
    @Test func kerberosReasonWithoutItsLines() {
        let problem = Log.line(
            "ERROR", "com.winpr.sspi.Kerberos",
            "[krb5glue_get_init_creds]: krb5_init_creds_get (Clock skew too great [-1])")
        var log = ConnectionLog()
        _ = log.consume(problem)
        log.note(.ended(.failed(.clockSkew)))
        #expect(log.entries.map(\.event) == [.ended(.failed(.clockSkew))])
    }

    /// A Kerberos reason of a failed reconnection is not listed twice either.
    @Test func kerberosReasonOfAReconnection() {
        var log = ConnectionLog()
        for line in [Log.gdiInit, Log.networkDisconnect, Log.reconnecting(0)] { _ = log.consume(line) }
        log.reconnectFailed(.clockSkew, line: Log.noCertificate)
        log.note(.ended(.failed(.clockSkew)))
        #expect(log.entries.filter { $0.event == .ended(.failed(.clockSkew)) }.count == 1)
        #expect(!log.entries.contains { $0.event == .reconnectFailed(.clockSkew) })
    }

    /// Only an outage right after the gateway's message is its time limit.
    @Test func gatewayMessageLongBeforeAnOutage() {
        var log = ConnectionLog()
        let lines = [
            Log.gdiInit,
            ConnectionLogTests.at(
                "10:00:00", "ERROR", "com.freerdp.core", "[rdg_x]: E_PROXY_REAUTH_AUTHN_FAILED [0x80075A2A]"),
            ConnectionLogTests.at("11:00:00", "INFO", "com.freerdp.client.common", "[x]: Network disconnect!"),
        ]
        for line in lines { _ = log.consume(line) }
        #expect(log.entries.last?.event == .connectionInterrupted)
    }

    /// A module that failed before telling about itself: nothing, not a bare version.
    @Test func moduleWithoutInfo() {
        #expect(PKCS11Probe.info(of: cg_card_probe_result()).module.isEmpty)
    }

    /// A pulled token takes its reader along: "no service" is harmless while it is out, also the
    /// answers just before macOS reported it; with the card in, it is a problem.
    @Test func readerGoneWhileTheCardIsOut() throws {
        func answer(_ time: String, _ code: String) -> String {
            ConnectionLogTests.at(
                time, "ERROR", "com.freerdp.utils.smartcard.call",
                "[scard_log_status_error_wlog]: SCardListReadersW failed with error \(code) [-1]")
        }
        let date = try #require(ConnectionLog.timeFormat.date(from: "20:05:31"))
        var log = ConnectionLog()
        _ = log.consume(Log.gdiInit)
        #expect(log.consume(answer("20:05:30", "SCARD_E_NO_SERVICE")) == .error)
        log.cardInReader(false, at: date)
        #expect(log.consume(answer("20:05:31", "SCARD_E_NO_SERVICE")) == .harmless)
        #expect(log.consume(answer("20:05:31", "SCARD_E_READER_UNAVAILABLE")) == .harmless)
        #expect(log.entries.map(\.event) == [.desktopShown, .cardRemoved])
        log.cardInReader(true, at: date)
        #expect(log.consume(answer("20:05:40", "SCARD_E_NO_SERVICE")) == .error)
        #expect(log.entries.count == 4)
    }
}
