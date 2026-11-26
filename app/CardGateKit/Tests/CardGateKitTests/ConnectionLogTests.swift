import Foundation
import Testing

@testable import CardGateKit

/// The log window: no warning or error when everything works, the important events in words.
struct ConnectionLogTests {
    /// A successful session with NLA the user then disconnected, as the client logs it (addresses
    /// replaced; the smart card trace left out).
    static let successfulSession = [
        at(
            "16:55:05", "WARN", "com.freerdp.client.common.cmdline",
            "[warn_credential_args]: Using /smartcard-logon is insecure"),
        at(
            "16:55:05", "WARN", "com.freerdp.client.common.cmdline",
            "[warn_credential_args]: Passing credentials or secrets via command line might expose these"),
        at(
            "16:55:05", "INFO", "com.freerdp.client.SDL",
            "[queryDisplay]: display 1: 38 points at the top left out (notch)"),
        at(
            "16:55:05", "WARN", "com.freerdp.core.nego",
            "[nego_enable_aad]: This build does not support AAD security, disabling."),
        at(
            "16:55:24", "INFO", "com.freerdp.core.gateway.rdg_sc",
            "[rdg_sc_new]: smart card ready for RD Gateway authentication (module /m.dylib, slot 0)"),
        at(
            "16:55:26", "INFO", "com.freerdp.core.gateway.rdg",
            "[rdg_process_extauth_sc]: RD Gateway smart card authentication done"),
        at(
            "16:55:50", "DEBUG", "com.freerdp.core.nego",
            "[nego_connect]: Negotiated [HYBRID_EX][0x00000008] security"),
        at(
            "16:55:50", "WARN", "com.freerdp.crypto",
            "[verify_cb]: Certificate verification failure 'self-signed certificate (18)' at stack position 0"),
        at(
            "16:55:50", "WARN", "com.freerdp.crypto",
            "[verify_cb]: CN = pc01.example.com"),
        at(
            "16:55:50", "ERROR", "com.winpr.library",
            "[GetProcAddress]: GetProcAddress: could not find procedure krb5_get_etype_info: invalid handle"),
        at(
            "16:55:50", "WARN", "com.winpr.sspi.Kerberos",
            "[krb_log_context_encryption]: kerberos implementation does not support 'krb5_get_etype_info'"),
        at(
            "16:56:05", "ERROR", "com.winpr.sspi.Kerberos",
            "[kerberos_QueryContextAttributesCommon]: TODO: QueryContextAttributes implement "
                + "ulAttribute=0x00000456"),
        at(
            "16:56:05", "WARN", "com.winpr.sspi",
            "[winpr_QueryContextAttributesA]: QueryContextAttributesA status SEC_E_UNSUPPORTED_FUNCTION [0x80090302]"),
        at(
            "16:56:05", "INFO", "com.freerdp.gdi",
            "[gdi_init_ex]: Local framebuffer format  PIXEL_FORMAT_BGRA32"),
        at(
            "16:56:05", "INFO", "com.freerdp.gdi",
            "[gdi_init_ex]: Remote framebuffer format PIXEL_FORMAT_BGRA32"),
        at(
            "16:56:29", "INFO", "com.freerdp.client.SDL",
            "[sdl_save_session_info]: signed in: releasing the modifier keys not held"),
        at(
            "16:56:40", "ERROR", "com.winpr.clipboard",
            "[ClipboardGetData]: No synthesizer for format CF_RAW [0x00000000] --> image/bmp [0x0000c005]"),
        at(
            "16:57:52", "INFO", "com.freerdp.client.SDL",
            "[confirmDisconnect]: disconnect confirmed by the user"),
        at(
            "16:57:52", "ERROR", "com.freerdp.core",
            "[abortConnect]: ERRCONNECT_CONNECT_CANCELLED [0x0002000B]"),
        at(
            "16:57:52", "WARN", "com.freerdp.core.transport",
            "[transport_ssl_cb]: Unhandled SSL error (where=SSL_CB_ALERT|SSL_CB_WRITE]{0x00004008}, ret=562)"),
        at(
            "16:57:52", "INFO", "com.freerdp.client.common",
            "[client_auto_reconnect_ex]: Network disconnect!"),
        at(
            "16:57:52", "WARN", "com.freerdp.client.common",
            "[client_auto_reconnect_ex]: Connection aborted by user"),
        at(
            "16:57:52", "ERROR", "com.freerdp.core.transport",
            "[transport_default_write]: BIO_should_retry retries exceeded"),
        at(
            "16:57:52", "WARN", "com.freerdp.core",
            "[mcs_send_disconnect_provider_ultimatum]: failed to send DisconnectProviderUltimatum, status=-1"),
        at(
            "16:57:52", "ERROR", "com.freerdp.channels.rdpdr.client",
            "[rdpdr_send]: pVirtualChannelWriteEx failed with CHANNEL_RC_BAD_CHANNEL_HANDLE [00000007]"),
        at(
            "16:57:52", "ERROR", "com.freerdp.channels.smartcard.client",
            "[smartcard_context_queue_loop]: failed with CHANNEL_RC_BAD_CHANNEL_HANDLE [7]"),
    ]

    static func at(_ time: String, _ level: String, _ tag: String, _ message: String) -> String {
        "[\(time):000] [81611:6bf93001] [\(level)][\(tag)] - \(message)"
    }

    static func read(_ lines: [String], into log: inout ConnectionLog) -> [LogLineKind] {
        lines.map { log.consume($0) }
    }

    @Test func successfulSessionHasNoWarningOrError() {
        var log = ConnectionLog()
        log.note(.connecting)
        let kinds = Self.read(Self.successfulSession, into: &log)
        log.note(.ended(.closedByUser))

        #expect(!kinds.contains(.warning))
        #expect(!kinds.contains(.error))
        #expect(kinds.filter { $0 == .harmless }.count == 17)
        #expect(log.entries.allSatisfy { $0.event.severity == .info })
        #expect(
            log.entries.map(\.event) == [
                .connecting, .signingInToGateway, .gatewayAccepted, .security(.nla), .desktopShown, .signedIn,
                .ended(.closedByUser),
            ])
        #expect(log.entries[1].time == "16:55:24")
    }

    /// The gateway's certificate must be trusted by the system: a failure there is not harmless.
    @Test func certificateWarningBeforeTheGatewayIsShown() {
        var log = ConnectionLog()
        let kinds = Self.read(Array(Self.successfulSession[7...8]), into: &log)
        #expect(kinds == [.warning, .warning])
        #expect(
            log.entries.map(\.event) == [
                .unknown(
                    "Certificate verification failure 'self-signed certificate (18)' at stack position 0",
                    isError: false),
                .unknown("CN = pc01.example.com", isError: false),
            ])
    }

    /// Errors of closing the connection mean something only while the session should go on.
    @Test func closingErrorsCountWithoutDisconnect() {
        var log = ConnectionLog()
        let line = Self.successfulSession[22]
        #expect(log.consume(line) == .error)
        log.stopRequested()
        #expect(log.consume(line) == .harmless)
    }

    @Test func rdpSecurityIsAWarning() {
        var log = ConnectionLog()
        _ = log.consume(
            Log.line("DEBUG", "com.freerdp.core.nego", "[nego_connect]: Negotiated [RDP][0x00000000] security"))
        #expect(log.entries.map(\.event) == [.security(.rdp)])
        #expect(log.entries[0].event.severity == .warning)
        #expect(ConnectionLogEvent.security(.tls).severity == .info)
    }

    /// An outage: one warning, its cause and the steps of reconnecting are not listed.
    @Test func outageAndReconnect() {
        var log = ConnectionLog()
        let lines = [
            Log.gdiInit, Log.transportFailed, Log.networkDisconnect, Log.reconnecting(1), Log.transportFailed,
            Log.reconnecting(2), Log.cardReady, Log.gatewayDone, Log.reconnected,
        ]
        _ = Self.read(lines, into: &log)
        #expect(
            log.entries.map(\.event) == [
                .desktopShown, .connectionInterrupted, .reconnecting(attempt: 2, total: 10),
                .reconnecting(attempt: 3, total: 10), .reconnected,
            ])
    }

    /// An unknown warning appears in the important messages; failures the app explains do not.
    @Test func unknownProblemsAreShown() {
        var log = ConnectionLog()
        _ = log.consume(Log.line("ERROR", "com.freerdp.core", "[x]: something new"))
        _ = log.consume(Log.wrongPIN)
        _ = log.consume(
            Log.line("ERROR", "com.freerdp.core", "[rdp_set_error_info]: ERRINFO_RPC_INITIATED_DISCONNECT [0x00010001]")
        )
        log.note(.ended(.failed(.disconnectedByServer)))
        #expect(
            log.entries.map(\.event) == [
                .unknown("something new", isError: true), .ended(.failed(.disconnectedByServer)),
            ])
        #expect(log.entries.map(\.event.severity) == [.error, .warning])
    }

    @Test func certificateEvents() {
        var log = ConnectionLog()
        _ = log.consume(
            Log.line(
                "INFO", "com.freerdp.crypto",
                "[tls]: changed certificate of pc01:3389 confirmed by its fingerprint, replacing the stored one."))
        _ = log.consume(
            Log.line(
                "INFO", "com.freerdp.crypto",
                "[tls]: changed certificate of pc01:3389 verified by Kerberos, replacing the stored one."))
        #expect(log.entries.map(\.event) == [.changedCertificateTrusted, .renewedCertificateVerified])
        #expect(log.entries.map(\.event.severity) == [.warning, .info])
    }

    @Test func parsing() throws {
        #expect(ConnectionLog.message(of: Self.successfulSession[0]) == "Using /smartcard-logon is insecure")
        #expect(ConnectionLog.message(of: "plain") == "plain")
        let numbers = try #require(ConnectionLog.numbers(in: Log.reconnecting(3), after: "Attempting reconnect ("))
        #expect(numbers.0 == 3 && numbers.1 == 10)
        #expect(ConnectionLog.numbers(in: "Attempting reconnect (x)", after: "Attempting reconnect (") == nil)
        #expect(ConnectionLog.time(of: "no time").count == 8)
    }

    /// Only what broke the connection just before an outage is left out, not older problems.
    @Test func outageKeepsEarlierProblems() {
        var log = ConnectionLog()
        _ = log.consume(Log.gdiInit)
        _ = log.consume(Self.at("10:00:00", "ERROR", "com.freerdp.core", "[x]: an hour before"))
        _ = log.consume(Self.at("11:00:00", "ERROR", "com.freerdp.core", "[x]: the transport broke"))
        _ = log.consume(Self.at("11:00:01", "INFO", "com.freerdp.client.common", "[x]: Network disconnect!"))
        #expect(
            log.entries.map(\.event) == [
                .desktopShown, .unknown("an hour before", isError: true), .connectionInterrupted,
            ])
    }

    /// Once reconnected, closing errors count again, and a later outage is reported.
    @Test func reconnectEndsTheEnding() {
        var log = ConnectionLog()
        _ = log.consume(Log.gdiInit)
        _ = log.consume(Log.line("INFO", "com.freerdp.core", "[rdp_print_errinfo]: ERRINFO_IDLE_TIMEOUT"))
        #expect(log.consume(Self.successfulSession[22]) == .harmless)
        _ = log.consume(Log.reconnected)
        #expect(log.consume(Self.successfulSession[22]) == .error)
        _ = log.consume(Log.networkDisconnect)
        #expect(log.entries.last?.event == .connectionInterrupted)
    }

    /// Kerberos problems are listed only when the connection then fails.
    @Test func kerberosProblemsOnlyWhenFailing() {
        let problem = Log.line(
            "ERROR", "com.winpr.sspi.Kerberos", "[krb5glue_get_init_creds]: krb5_init_creds_get (KDC unreachable [-1])")
        var failing = ConnectionLog()
        _ = failing.consume(problem)
        #expect(failing.entries.isEmpty)
        failing.note(.ended(.failed(.kerberosFailed)))
        #expect(
            failing.entries.map(\.event) == [
                .unknown("krb5_init_creds_get (KDC unreachable [-1])", isError: true), .ended(.failed(.kerberosFailed)),
            ])

        var recovered = ConnectionLog()
        _ = recovered.consume(problem)
        _ = recovered.consume(Log.gdiInit)
        recovered.note(.ended(.closedByUser))
        #expect(recovered.entries.map(\.event) == [.desktopShown, .ended(.closedByUser)])
    }

    @Test func revisionFollowsEntries() {
        var log = ConnectionLog()
        _ = log.consume(Self.successfulSession[0])  // harmless: no entry
        #expect(log.revision == 0)
        log.note(.connecting)
        #expect(log.revision == 1)
    }

    /// Without reconnecting an outage is reported by the end event, not as "Reconnecting…".
    @Test func outageWithoutReconnecting() {
        var log = ConnectionLog(reconnects: false)
        _ = log.consume(Log.gdiInit)
        _ = log.consume(Log.networkDisconnect)
        #expect(log.entries.map(\.event) == [.desktopShown])
    }

    /// Signing out in Windows or cancelling a reconnect is not a problem.
    @Test func endingLinesAreHarmless() {
        var log = ConnectionLog()
        #expect(
            log.consume(Log.line("ERROR", "com.freerdp.core", "[x]: ERRINFO_LOGOFF_BY_USER [0x0000000C]")) == .harmless)
        #expect(log.consume(Log.line("ERROR", "com.freerdp.core", "[x]: ERRINFO_IDLE_TIMEOUT [0x00000003]")) == .error)
        var cancelling = ConnectionLog()
        #expect(cancelling.consume(SessionLogReconnectTests.abortedByUser) == .harmless)
    }

    /// The computer's certificate from an internal certification authority is trusted on first use
    /// too; the fingerprint decides.
    @Test func computerCertificateProblemsAreHarmless() {
        var log = ConnectionLog()
        _ = log.consume(Log.gatewayDone)
        let issuer = Log.line(
            "WARN", "com.freerdp.crypto",
            "[verify_cb]: Certificate verification failure 'unable to get local issuer certificate (20)'")
        let subject = Log.line("WARN", "com.freerdp.crypto", "[verify_cb]: CN = pc01.example.com")
        #expect(log.consume(issuer) == .harmless)
        #expect(log.consume(subject) == .harmless)
        // A subject line without a certificate problem before it stays a warning.
        #expect(log.consume(subject) == .warning)
    }

    /// Clipboard formats without a conversion (e.g. an image copied on the Mac).
    @Test func clipboardConversionsAreHarmless() {
        var log = ConnectionLog()
        let line = Log.line(
            "ERROR", "com.winpr.clipboard",
            "[ClipboardGetData]: No synthesizer for format image/png [0x0000c00e] --> HTML Format [0x0000c003]")
        #expect(log.consume(line) == .harmless)
        #expect(log.entries.isEmpty)
    }

    /// FreeRDP's own optimizations and thread priorities: written to the log, shown gray.
    @Test func clientLimitsAreHarmless() {
        var log = ConnectionLog()
        #expect(
            log.consume(Log.line("WARN", "com.winpr.thread", "[x]: pthread_setschedprio(0) not implemented"))
                == .harmless)
        #expect(
            log.consume(Log.line("WARN", "x", "[x]: TODO: Implement neon optimized version of this function"))
                == .harmless)
    }

    /// The client reconnects after an error of the computer without an outage: still an interruption.
    @Test func reconnectAfterComputerError() {
        var log = ConnectionLog()
        _ = log.consume(Log.gdiInit)
        _ = log.consume(Log.line("INFO", "com.freerdp.core", "[x]: ERRINFO_GRAPHICS_SUBSYSTEM_FAILED"))
        _ = log.consume(Log.reconnecting(0))
        #expect(log.consume(Self.successfulSession[22]) == .error)  // not part of an ending any more
        _ = log.consume(Log.reconnected)
        #expect(
            log.entries.map(\.event) == [
                .desktopShown, .connectionInterrupted, .reconnecting(attempt: 1, total: 10), .reconnected,
            ])
    }

    /// Kerberos lines after the desktop appeared are not about signing in.
    @Test func kerberosAfterDesktopIsNotListed() {
        var log = ConnectionLog()
        _ = log.consume(Log.gdiInit)
        _ = log.consume(Log.line("WARN", "com.winpr.sspi.Kerberos", "[x]: ticket message"))
        log.note(.ended(.failed(.connectionLost)))
        #expect(log.entries.map(\.event) == [.desktopShown, .ended(.failed(.connectionLost))])
    }

    /// The last Kerberos problems are kept: they say why it failed.
    @Test func keepsTheLastKerberosProblems() {
        var log = ConnectionLog()
        for number in 1...25 {
            _ = log.consume(Log.line("WARN", "com.winpr.sspi.Kerberos", "[x]: problem \(number)"))
        }
        log.note(.ended(.failed(.kerberosFailed)))
        #expect(log.entries.first?.event == .unknown("problem 6", isError: false))
        #expect(log.entries.dropLast().last?.event == .unknown("problem 25", isError: false))
    }
}

extension ConnectionLogTests {
    /// The controls in the title bar of the remote desktop window (patch 0023).
    @Test func titleBarRequests() {
        var log = ConnectionLog()
        let lines = [
            Log.line("INFO", "com.freerdp.client.SDL", "[sdl_run]: the user asked to show the connection log"),
            Log.line("INFO", "com.freerdp.client.SDL", "[changeScale]: desktop scale changed in the title bar: 150"),
            Log.line(
                "INFO", "com.freerdp.client.SDL",
                "[changeScale]: desktop scale changed in the title bar: the scale of each display"),
        ]
        #expect(lines.map { log.consume($0) } == [.normal, .normal, .normal])
        _ = log.consume(
            Log.line("INFO", "com.freerdp.client.SDL", "[changeScale]: desktop scale changed in the title bar: 150 %"))
        #expect(log.entries.map(\.event) == [.scaleChanged(150), .scaleChanged(nil)])
        #expect(log.entries.map(\.event.severity) == [.info, .info])
        #expect(TitleBarControls.asksForLog(lines[0]))
        #expect(!TitleBarControls.asksForLog(lines[1]))
        // Not the text quoted in another line.
        #expect(
            !TitleBarControls.asksForLog(
                Log.line("ERROR", "com.freerdp.core", "[rdg]: 'the user asked to show the connection log'")))
        _ = log.consume(Log.line("INFO", "com.freerdp.core", "[x]: desktop scale changed in the title bar: 300"))
        #expect(log.entries.count == 2)
    }
}
