import Foundation

/// The texts of the client log the parser recognizes.
extension SessionLogParser {
    /// Texts of the FreeRDP log this parser depends on. A test checks that the bundled client still
    /// contains them, so a FreeRDP update cannot silently break the status display.
    public static let logMarkers =
        [
            "smart card ready for RD Gateway authentication",
            "RD Gateway smart card authentication done",
            "gdi_init_ex",
            "registered [",
            "no suitable smartcard certificates",
            "more than one suitable smartcard certificate",
            "FREERDP_SMARTCARD_CERT_SHA1",
            "WRONG PIN",
            "PIN is LOCKED",
            "certificate not trusted",
            "inner TLS certificate differs",
            "Network disconnect!",
            "Attempting reconnect (",
            "Reconnected (attempt",
            "Autoreconnect aborted by user",
            "- not retrying",
            "RD Gateway certificate changed",
            "client certificate has no RSA key",
            "Credential prompt cancelled",
            "ERRCONNECT_CONNECT_CANCELLED",
            "ERRCONNECT_SECURITY_NEGO_CONNECT_FAILED",
            "ERRCONNECT_CONNECT_TRANSPORT_FAILED",
            "ERRINFO_LOGOFF_BY_USER",
            "ERRINFO_LOGON_TIMEOUT",
            "nego_process_negotiation_failure",
            "ERRCONNECT_HYBRID_REQUIRED_BY_SERVER",
            "ERRINFO_RPC_INITIATED_LOGOFF",
            "ERRINFO_DISCONNECTED_BY_OTHER_CONNECTION",
            "ERRINFO_RPC_INITIATED_DISCONNECT_BY_USER",
            "ERRINFO_IDLE_TIMEOUT",
            "ERRINFO_RPC_INITIATED_DISCONNECT",
            "Negotiated %s security",
            "SSL_NOT_ALLOWED_BY_SERVER",
            "HYBRID_REQUIRED_BY_SERVER",
            "SSL_REQUIRED_BY_SERVER",
            "SSL_WITH_USER_AUTH_REQUIRED_BY_SERVER",
            "selected_protocol: %s",
            "RequestedProtocols: %s",
            "Enabling RDP security: %s",
            "Enabling TLS security: %s",
            "Enabling NLA security: %s",
            "changed since it was first trusted",
            "new fingerprint %s",
            "FREERDP_ACCEPT_CHANGED_CERTIFICATE",
            "verified by Kerberos",
            "Kerberos did not verify the computer",
            "Early User Auth active: FAILURE",
            "com.winpr.sspi.Kerberos",
            "Unexpected HTTP status: %s",
            "ERRCONNECT_ACCOUNT_DISABLED",
            "ERRCONNECT_ACCOUNT_LOCKED_OUT",
            "ERRCONNECT_ACCOUNT_EXPIRED",
            "ERRCONNECT_ACCOUNT_RESTRICTION",
            "ERRCONNECT_LOGON_TYPE_NOT_GRANTED",
            "E_PROXY_RAP_ACCESSDENIED",
            "E_PROXY_NAP_ACCESSDENIED",
            "E_PROXY_MAXCONNECTIONSREACHED",
            "E_PROXY_UNSUPPORTED_AUTHENTICATION_METHOD",
            "ERRINFO_SERVER_INSUFFICIENT_PRIVILEGES",
            "ERRINFO_SERVER_DENIED_CONNECTION",
            "ERRINFO_LICENSE_NO_LICENSE_SERVER",
        ] + gatewayProxyCodes + Array(windowsCodes.keys).sorted()

    /// Error texts in the order they are checked; the first match wins.
    static let knownFailures: [(text: String, failure: SessionFailure)] =
        [
            ("no suitable smartcard certificates", .noCertificate),
            ("WRONG PIN", .wrongPIN),
            // The card refused the sign-in with another code: the PIN is never offered again (patch 0001).
            ("- not retrying", .cardRefusedLogin),
            // The computer's certificate changed (patch 0016); before "certificate not trusted", logged after it.
            ("changed since it was first trusted", .computerCertificateChanged),
            ("certificate not trusted", .untrustedCertificate),
            // Only AUTHZ_ACCESS_DENIED: the account is not allowed; other results fail the sign-in.
            ("Early User Auth active: FAILURE authorization result 0x00000005", .notAllowedOnComputer),
            ("RD Gateway certificate changed", .gatewayCertificateChanged),
            ("inner TLS certificate differs", .untrustedCertificate),
            ("more than one suitable smartcard certificate", .multipleCertificates),
            ("PIN is LOCKED", .cardLocked),
            ("client certificate has no RSA key", .unsupportedCardKey),
            // The computer refused the account in network level authentication.
            ("ERRCONNECT_ACCOUNT_DISABLED", .accountDisabled),
            ("ERRCONNECT_ACCOUNT_LOCKED_OUT", .accountLockedOut),
            ("ERRCONNECT_ACCOUNT_EXPIRED", .accountExpired),
            ("ERRCONNECT_ACCOUNT_RESTRICTION", .accountRestricted),
            ("ERRCONNECT_LOGON_TYPE_NOT_GRANTED", .notAllowedOnComputer),
            // The gateway's policies: for the computer (RAP) and for the user (CAP, called NAP).
            ("E_PROXY_RAP_ACCESSDENIED", .computerNotAllowedByGateway),
            ("E_PROXY_NAP_ACCESSDENIED", .gatewayDenied),
            ("E_PROXY_MAXCONNECTIONSREACHED", .gatewayTemporarilyUnavailable),
            ("E_PROXY_UNSUPPORTED_AUTHENTICATION_METHOD", .gatewayNoSmartCard),
            // Windows ended the connection before the desktop was shown (after, `serverEnd`).
            ("ERRINFO_LICENSE_", .noLicense),
            ("ERRCONNECT_DNS_NAME_NOT_FOUND", .gatewayUnreachable),
            ("ERRCONNECT_CONNECT_FAILED", .gatewayUnreachable),
            ("ERRCONNECT_ACCESS_DENIED", .gatewayDenied),
            ("ERRCONNECT_AUTHENTICATION_FAILED", .gatewayDenied),
            ("ERRCONNECT_CONNECT_TRANSPORT_FAILED", .computerUnreachable),
            ("ERRCONNECT_HYBRID_REQUIRED_BY_SERVER", .securityRefused),
        ] + gatewayProxyCodes.map { ($0, .computerUnreachable) }
        + windowsCodes.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }

    /// Windows' reasons for ending a connection that have a failure of their own ([MS-RDPBCGR] 2.2.5.1.1).
    static let windowsCodes: [String: SessionFailure] = [
        "ERRINFO_SERVER_INSUFFICIENT_PRIVILEGES": .notAllowedOnComputer,
        "ERRINFO_SERVER_DENIED_CONNECTION": .computerRefused,
        "ERRINFO_SERVER_DWM_CRASH": .windowsFailed,
        "ERRINFO_SERVER_WINLOGON_CRASH": .windowsFailed,
        "ERRINFO_SERVER_CSRSS_CRASH": .windowsFailed,
        "ERRINFO_OUT_OF_MEMORY": .windowsFailed,
    ]

    /// Why Kerberos failed, from MIT krb5's messages (they may name the principal or realm, e.g.
    /// "Server 'TERMSRV/pc01@EXAMPLE.COM' not found in Kerberos database"); `nil` for another reason.
    static func kerberosProblem(in line: String) -> SessionFailure? {
        if line.contains("Clock skew too great") { return .clockSkew }
        if line.contains("Cannot contact any KDC") || line.contains("Cannot resolve network address for KDC") {
            return .domainUnreachable
        }
        // Not "Cannot find KDC" (no KDC known for a realm): that may be the computer's realm or the
        // account's in another domain; the generic failure lists Kerberos' own lines.
        if line.range(of: #"Server .*not found in Kerberos database"#, options: .regularExpression) != nil {
            return .computerUnknownToDomain
        }
        if line.range(of: #"Client .*not found in Kerberos database"#, options: .regularExpression) != nil {
            return .accountUnknownToDomain
        }
        if line.contains("credentials have been revoked") { return .accountRevoked }
        if line.contains("KDC not trusted") { return .domainNotTrusted }
        let certificate = [
            "Client not trusted", "Invalid certificate", "Can't verify certificate", "Revocation status unknown",
            "Revocation status unavailable",
        ]
        return certificate.contains(where: line.contains) ? .cardCertificateRejected : nil
    }

    /// The gateway answered that it is overloaded or in maintenance ("… [503]").
    static func gatewayTemporarilyUnavailable(_ line: String) -> Bool {
        line.contains("Unexpected HTTP status: ") && ["[502]", "[503]", "[504]"].contains(where: line.contains)
    }

    /// The gateway closed the channel to the computer: it could not reach it or the computer dropped
    /// the connection (e.g. offered RDP security it does not accept) – once it accepted the sign-in;
    /// before, an error of its own. Other gateway errors (its policy, its sign-in) keep their meaning.
    static let gatewayProxyCodes = ["E_PROXY_INTERNALERROR", "E_PROXY_TS_CONNECTFAILED", "E_PROXY_CONNECTIONABORTED"]

    /// A Kerberos call that failed: "[krb5glue_get_init_creds]: krb5_init_creds_get (message [code])".
    static func isKerberosError(_ line: String) -> Bool {
        line.contains("[ERROR][com.winpr.sspi.Kerberos]")
            && line.range(of: #"\]: krb5_[a-z_]+ \("#, options: .regularExpression) != nil
    }

    /// "Negotiated [HYBRID_EX][0x00000008] security" → NLA.
    static func negotiatedMethod(in line: String) -> SecurityMethod? {
        guard line.contains("Negotiated ["),
            let range = line.range(of: #"Negotiated \[[A-Z_]+\]"#, options: .regularExpression)
        else { return nil }
        return SecurityMethod(negotiatedProtocol: String(line[range].dropFirst("Negotiated [".count).dropLast()))
    }

    static func failure(in line: String) -> SessionFailure? {
        guard line.contains("[ERROR]"), !line.contains("ERRCONNECT_CONNECT_CANCELLED") else { return nil }
        if let known = knownFailures.first(where: { line.contains($0.text) }) { return known.failure }
        if let range = line.range(of: #"ERRCONNECT_[A-Z_]+"#, options: .regularExpression) {
            return .other(String(line[range]))
        }
        return nil
    }
}
