import Foundation
import Testing

@testable import CardGateKit

/// After an outage the client reconnects on its own (CardGate → Settings, patch 0012 logs success).
struct SessionLogReconnectTests {
    static let abortedByUser = Log.line(
        "WARN", "com.freerdp.client.common", "[client_auto_reconnect_cancelled]: Autoreconnect aborted by user")

    /// The client reconnects on its own; the connection steps it goes through again are not shown.
    @Test func reconnectsAfterAnOutage() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.transportFailed)
        parser.consume(Log.networkDisconnect)
        #expect(parser.consume(Log.reconnecting(0)) == .reconnecting)
        #expect(parser.phase.hasDesktop)
        #expect(parser.consume(Log.transportFailed) == nil)  // the network is still down
        #expect(parser.consume(Log.reconnecting(1)) == nil)
        #expect(parser.consume(Log.cardReady) == nil)
        #expect(parser.consume(Log.gatewayDone) == nil)
        #expect(parser.consume(Log.reconnected) == .connected)

        // Windows' reason for ending an earlier connection does not end the restored one.
        var restored = SessionLogParser()
        restored.consume(Log.gdiInit)
        restored.consume(Log.networkDisconnect)
        restored.consume(Log.reconnecting(0))
        restored.consume(
            Log.line("INFO", "com.freerdp.core", "[rdp_print_errinfo]: ERRINFO_IDLE_TIMEOUT (0x00000003)"))
        restored.consume(Log.reconnected)
        #expect(restored.consume(Log.networkDisconnect) == nil)
        #expect(restored.consume(Log.reconnecting(0)) == .reconnecting)

        // Later it breaks again and the client gives up: the earlier failure is forgotten.
        parser.consume(Log.networkDisconnect)
        parser.consume(Log.reconnecting(0))
        #expect(parser.processExited(status: 0) == .ended(.failed(.connectionLost)))
    }

    /// A reconnection the card or gateway refuses is reported as such: the user has to act.
    @Test func reconnectionRefusedByTheCard() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.networkDisconnect)
        parser.consume(Log.reconnecting(0))
        parser.consume(Log.transportFailed)  // the network was still down
        parser.consume(Log.reconnecting(1))
        parser.consume(Log.wrongPIN)
        parser.consume(Log.transportFailed)
        #expect(parser.processExited(status: 1) == .ended(.failed(.wrongPIN)))
    }

    /// Closing the window while reconnecting: no cancel error is logged, only that the loop stopped.
    @Test func closingWhileReconnectingIsNotAnError() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.networkDisconnect)
        parser.consume(Log.reconnecting(0))
        parser.consume(Log.transportFailed)
        let aborted = Log.line(
            "INFO", "com.freerdp.client.common", "[client_auto_reconnect_do]: Autoreconnect aborted by user")
        #expect(parser.consume(aborted) == .ended(.closedByUser))
    }

    /// A sign-in the card refused with another code than a wrong PIN: maybe the PIN, maybe the card.
    @Test func cardRefusedTheSignIn() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.networkDisconnect)
        parser.consume(Log.reconnecting(0))
        let refused = "[sc_pkcs11_open]: C_Login failed 0x00000006 - not retrying"
        parser.consume(Log.line("ERROR", "com.freerdp.core.gateway.rdg_sc", refused))
        parser.consume(
            Log.line("ERROR", "com.freerdp.core.gateway.rdg", "[rdg_sc_init]: the card refused the PIN before"))
        #expect(parser.processExited(status: 1) == .ended(.failed(.cardRefusedLogin)))
        // A card that was not there to check it is not a wrong PIN.
        let absent = Log.line("ERROR", "x", "[sc_pkcs11_open]: C_Login failed 0x000000E0")
        #expect(SessionLogParser.failure(in: absent) == nil)
    }

    /// FreeRDP also reconnects after some server errors; the error then belongs to the old connection.
    @Test func reconnectsAfterAServerError() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        let serverError = "[rdp_set_error_info]: ERRINFO_GRAPHICS_SUBSYSTEM_FAILED [0x000010F5]"
        parser.consume(Log.line("ERROR", "com.freerdp.core", serverError))
        #expect(parser.consume(Log.reconnecting(0)) == .reconnecting)
        #expect(parser.consume(Log.reconnected) == .connected)
        #expect(parser.consume(Log.networkDisconnect) == nil)  // reconnecting again, not ended
        #expect(parser.processExited(status: 0) == .ended(.failed(.connectionLost)))
    }

    /// Disconnect while reconnecting is a normal end, as is the cancelled PIN dialog.
    @Test func stoppingWhileReconnecting() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.networkDisconnect)
        parser.consume(Log.reconnecting(0))
        parser.stopRequested()
        parser.consume(Log.wrongPIN)
        #expect(parser.processExited(status: 0) == .ended(.closedByUser))
    }

    /// The server ended an attempt (e.g. the session was taken over): reconnecting goes on, and its
    /// reason is shown when the client gives up.
    @Test func serverEndsWhileReconnecting() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.networkDisconnect)
        parser.consume(Log.reconnecting(0))
        parser.consume(
            Log.line("ERROR", "com.freerdp.core", "[rdp_set_error_info]: ERRINFO_DISCONNECTED_BY_OTHER_CONNECTION"))
        #expect(parser.consume(Log.reconnecting(1)) == nil)
        #expect(parser.processExited(status: 0) == .ended(.failed(.sessionTakenOver)))
    }

    /// The reason the server gave for the connection before does not explain a failed reconnection.
    @Test func earlierServerReasonIsForgotten() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        let serverError = "[rdp_set_error_info]: ERRINFO_GRAPHICS_SUBSYSTEM_FAILED [0x000010F5]"
        parser.consume(Log.line("ERROR", "com.freerdp.core", serverError))
        parser.consume(Log.reconnecting(0))
        #expect(parser.processExited(status: 0) == .ended(.failed(.connectionLost)))
    }

    /// A crash is a crash, even after the connection broke.
    @Test func crashWhileReconnecting() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.networkDisconnect)
        parser.consume(Log.reconnecting(0))
        #expect(parser.processExited(status: SIGSEGV, crashed: true) == .ended(.failed(.other("signal 11"))))
    }

    /// The card is used again only with the gateway certificate checked before connecting.
    @Test func gatewayCertificateChangedWhileConnected() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.networkDisconnect)
        parser.consume(Log.reconnecting(0))
        let changed = "[rdg_sc_same_gateway]: the RD Gateway certificate changed since the session started"
        parser.consume(Log.line("ERROR", "com.freerdp.core.gateway.rdg", changed))
        parser.consume(Log.line("ERROR", "com.freerdp.core", "[rdg_sc_init]: ERRCONNECT_ACCESS_DENIED [0x00020016]"))
        #expect(parser.processExited(status: 1) == .ended(.failed(.gatewayCertificateChanged)))
    }

    /// A PIN attempt used while reconnecting is reported even when the user then disconnects.
    @Test func refusedPINIsShownAfterDisconnect() {
        var parser = SessionLogParser()
        parser.consume(Log.gdiInit)
        parser.consume(Log.networkDisconnect)
        parser.consume(Log.reconnecting(0))
        parser.consume(Log.wrongPIN)
        parser.stopRequested()
        // The client logs the stop of the reconnection loop before it exits.
        #expect(parser.consume(Self.abortedByUser) == .ended(.failed(.wrongPIN)))
        #expect(parser.processExited(status: 0) == .ended(.failed(.wrongPIN)))
    }

    /// A certificate the system trusts but the client does not: not public, not an interception.
    @Test func certificateNotPublicWhileReconnecting() {
        var parser = SessionLogParser(gatewayTrustedBySystem: true)
        parser.consume(Log.gdiInit)
        parser.consume(Log.networkDisconnect)
        parser.consume(Log.reconnecting(0))
        parser.consume(Log.line("ERROR", "com.freerdp.crypto", "[tls_verify_certificate]: certificate not trusted"))
        // Closing the window then does not hide it.
        #expect(parser.consume(Self.abortedByUser) == .ended(.failed(.gatewayCertificateNotPublic)))
    }
}
