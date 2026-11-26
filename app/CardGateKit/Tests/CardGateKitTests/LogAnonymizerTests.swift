import Foundation
import Testing

@testable import CardGateKit

/// The saved log names nothing of the user's environment.
struct LogAnonymizerTests {
    let anonymizer = LogAnonymizer(
        computer: "pc01.corp.example.com", gateway: "rdg.example.com", name: "Office PC", home: "/Users/jane")

    @Test func commandLine() {
        let line =
            "CardGate: /v:pc01.corp.example.com /title:Office PC – CardGate "
            + "/gateway:g:rdg.example.com,type:http,usage-method:direct,auth:smartcard /smartcard:Example Reader"
        #expect(
            anonymizer.anonymize(line)
                == "CardGate: /v:*** /title:*** – CardGate /gateway:g:***,type:http,usage-method:direct,auth:smartcard "
                + "/smartcard:Example Reader")
    }

    @Test func namesInOtherLines() {
        #expect(anonymizer.anonymize("[verify_cb]: CN = PC01.corp.example.com") == "[verify_cb]: CN = ***")
        #expect(anonymizer.anonymize("realm CORP.EXAMPLE.COM, host PC01") == "realm ***, host ***")
        // Whole names only.
        #expect(anonymizer.anonymize("pc012 and xpc01") == "pc012 and xpc01")
        #expect(
            anonymizer.anonymize("krb5 (Server 'TERMSRV/pc01.corp.example.com@CORP.EXAMPLE.COM' not found)")
                == "krb5 (Server '***' not found)")
        #expect(anonymizer.anonymize("user jane@example.org") == "user ***")
        #expect(anonymizer.anonymize("dli_fname=/Users/jane/Apps/x.dylib") == "dli_fname=~/Apps/x.dylib")
    }

    /// The Windows account the client logs after signing in.
    @Test func windowsAccount() {
        let line =
            "[INFO][com.freerdp.client.common] - [client_common_save_session_info]: Logon Info V2 [CORP\\jane [2]]"
        #expect(
            anonymizer.anonymize(line)
                == "[INFO][com.freerdp.client.common] - [client_common_save_session_info]: Logon Info V2 [***]")
        #expect(anonymizer.anonymize(line + "\nnext").hasSuffix("[***]\nnext"))
    }

    /// An IP address is hidden whole; a domain of one label stays (it names nothing).
    @Test func terms() {
        #expect(LogAnonymizer.hostTerms("192.0.2.10", ownName: true) == ["192.0.2.10"])
        #expect(LogAnonymizer.hostTerms("pc01.example", ownName: true) == ["pc01.example", "pc01"])
        #expect(LogAnonymizer.hostTerms("rdg.corp.example", ownName: false) == ["rdg.corp.example", "corp.example"])
        #expect(LogAnonymizer(computer: "", gateway: nil, name: "PC").terms.isEmpty)
    }

    /// The log names what it connected to, also when the connection was changed since.
    @Test func namesFromTheCommandLine() {
        let log =
            "CardGate: /v:pc02.other.example:3389 /title:Lab Machine – CardGate "
            + "/gateway:g:rdg2.other.example,type:http /smartcard-logon\n"
            + "[verify_cb]: CN = PC02.other.example, lab machine"
        #expect(
            anonymizer.adding(commandLine: log).anonymize(log)
                == "CardGate: /v:***:3389 /title:*** – CardGate /gateway:g:***,type:http /smartcard-logon\n"
                + "[verify_cb]: CN = ***, lab machine")
        #expect(LogAnonymizer.withoutPort("[2001:db8::1]:3389") == "2001:db8::1")
        #expect(LogAnonymizer.withoutPort("pc01") == "pc01")
    }

    /// The log's own words stay: codes and functions joined by "_", common computer names, and a
    /// connection name outside the window title.
    @Test func logWordsStay() {
        let server = LogAnonymizer(computer: "server.corp.example.com", gateway: nil, name: "Windows")
        #expect(
            server.anonymize("ERRINFO_SERVER_DENIED_CONNECTION, rdp_server_x")
                == "ERRINFO_SERVER_DENIED_CONNECTION, rdp_server_x")
        #expect(
            server.anonymize("Signed in to Windows. /title:Windows – CardGate")
                == "Signed in to Windows. /title:*** – CardGate")
        #expect(server.anonymize("CN = server.corp.example.com") == "CN = ***")
        #expect(anonymizer.anonymize("ERRINFO_PC01_X pc01_y") == "ERRINFO_PC01_X pc01_y")
    }

    /// A connection name with " /" in it is hidden whole.
    @Test func titleWithSlash() {
        let log = "CardGate: /v:pc03 /title:Office / Prague – CardGate /gateway:g:rdg.example.com,type:http"
        #expect(
            LogAnonymizer(computer: "", gateway: nil, name: "").adding(commandLine: log).anonymize(log)
                == "CardGate: /v:*** /title:*** – CardGate /gateway:g:***,type:http")
    }
}
