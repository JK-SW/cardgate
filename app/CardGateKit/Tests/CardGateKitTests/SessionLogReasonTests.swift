import Foundation
import Testing

@testable import CardGateKit

/// Failures named after what the gateway, Windows or Kerberos said.
extension SessionLogSecurityTests {
    /// The gateway is full or in maintenance, or does not accept a card.
    @Test func gatewayUnavailable() {
        var busy = SessionLogParser()
        busy.consume(Log.cardReady)
        busy.consume(
            Log.line(
                "WARN", "com.freerdp.core.gateway.rdg",
                "[rdg_x]: Unexpected HTTP status: HTTP_STATUS_SERVICE_UNAVAIL [503]"))
        busy.consume(Log.line("ERROR", "com.freerdp.core", "[rdg_connect]: ERRCONNECT_CONNECT_FAILED [0x00020006]"))
        #expect(busy.processExited(status: 1) == .ended(.failed(.gatewayTemporarilyUnavailable)))

        var other = SessionLogParser()
        other.consume(
            Log.line(
                "WARN", "com.freerdp.core.gateway.rdg",
                "[rdg_x]: Unexpected HTTP status: HTTP_STATUS_SERVER_ERROR [500]"))
        #expect(other.processExited(status: 1) != .ended(.failed(.gatewayTemporarilyUnavailable)))

        var full = afterGateway()
        full.consume(Log.line("ERROR", "com.freerdp.core", "[rdg_x]: E_PROXY_MAXCONNECTIONSREACHED [0x80075AA2]"))
        #expect(full.processExited(status: 1) == .ended(.failed(.gatewayTemporarilyUnavailable)))

        var noCard = SessionLogParser()
        noCard.consume(
            Log.line("ERROR", "com.freerdp.core", "[rdg_x]: E_PROXY_UNSUPPORTED_AUTHENTICATION_METHOD [0x8007595F]"))
        #expect(noCard.processExited(status: 1) == .ended(.failed(.gatewayNoSmartCard)))
    }

    /// The computer refused the account in network level authentication.
    @Test(arguments: [
        ("ERRCONNECT_ACCOUNT_DISABLED", SessionFailure.accountDisabled),
        ("ERRCONNECT_ACCOUNT_LOCKED_OUT", .accountLockedOut),
        ("ERRCONNECT_ACCOUNT_EXPIRED", .accountExpired),
        ("ERRCONNECT_ACCOUNT_RESTRICTION", .accountRestricted),
        ("ERRCONNECT_LOGON_TYPE_NOT_GRANTED", .notAllowedOnComputer),
    ])
    func accountRefused(code: String, failure: SessionFailure) {
        var parser = afterGateway()
        parser.consume(Self.nego("HYBRID_EX", "0x00000008"))
        parser.consume(Log.line("ERROR", "com.freerdp.core", "[nla_recv_pdu]: \(code) [0x00020012]"))
        #expect(parser.processExited(status: 1) == .ended(.failed(failure)))
    }

    /// Kerberos said why the sign-in to the computer failed.
    @Test(arguments: [
        ("Clock skew too great", SessionFailure.clockSkew),
        (#"Cannot contact any KDC for realm 'CORP.EXAMPLE'"#, .domainUnreachable),
        (#"Cannot find KDC for realm "EXAMPLE.COM""#, .kerberosFailed),
        (#"Server 'TERMSRV/pc01.corp.example@CORP.EXAMPLE' not found in Kerberos database"#, .computerUnknownToDomain),
        (#"Client 'user@CORP.EXAMPLE' not found in Kerberos database"#, .accountUnknownToDomain),
        ("Client's credentials have been revoked", .accountRevoked),
        ("KDC not trusted", .domainNotTrusted),
        ("Revocation status unknown", .cardCertificateRejected),
        ("Client not trusted", .cardCertificateRejected),
    ])
    func kerberosReasons(message: String, failure: SessionFailure) {
        var parser = afterGateway()
        parser.consume(Self.nego("HYBRID_EX", "0x00000008"))
        parser.consume(
            Log.line(
                "ERROR", "com.winpr.sspi.Kerberos", "[krb5glue_get_init_creds]: krb5_init_creds_get (\(message) [-1])"))
        parser.consume(Self.authenticationFailed)
        #expect(parser.processExited(status: 1) == .ended(.failed(failure)))
        #expect(failure.isNLASignInFailure == ![.accountRevoked, .cardCertificateRejected].contains(failure))
    }

    /// The last Kerberos problem before the failure names it: an earlier one may have been recovered from.
    @Test func lastKerberosProblemWins() {
        var parser = afterGateway()
        parser.consume(Self.nego("HYBRID_EX", "0x00000008"))
        for message in ["Cannot contact any KDC for realm 'CORP.EXAMPLE'", "Clock skew too great"] {
            parser.consume(
                Log.line(
                    "ERROR", "com.winpr.sspi.Kerberos",
                    "[krb5glue_get_init_creds]: krb5_init_creds_get (\(message) [-1])"))
        }
        parser.consume(Self.authenticationFailed)
        #expect(parser.processExited(status: 1) == .ended(.failed(.clockSkew)))
    }

    /// A later Kerberos error of another kind (e.g. of the next call) does not hide the reason.
    @Test func laterUnknownKerberosErrorKeepsTheReason() {
        var parser = afterGateway()
        parser.consume(Self.nego("HYBRID_EX", "0x00000008"))
        for message in ["Clock skew too great", "Some other problem"] {
            parser.consume(
                Log.line(
                    "ERROR", "com.winpr.sspi.Kerberos",
                    "[krb5glue_get_init_creds]: krb5_init_creds_get (\(message) [-1])"))
        }
        parser.consume(Self.authenticationFailed)
        #expect(parser.processExited(status: 1) == .ended(.failed(.clockSkew)))
    }
}
