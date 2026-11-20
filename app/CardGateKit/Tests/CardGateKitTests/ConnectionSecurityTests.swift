import Foundation
import Security
import Testing

@testable import CardGateKit

struct ConnectionSecurityTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    static let nla = "/sec:nla:on,ext:on,tls:off,rdp:off"

    func plan(
        _ security: ConnectionSecurity, remembered: SecurityMethod? = nil, age: TimeInterval = 0, kerberos: Bool = true,
        nlaFailed: Bool = false
    ) -> SecurityPlan? {
        let remembered = remembered.map { RememberedSecurity(method: $0, date: now - age) }
        let needs = SecurityPlan.needsKerberos(security, remembered: remembered, nlaFailed: nlaFailed, at: now)
        return SecurityPlan.make(
            security, remembered: remembered, nlaFailed: nlaFailed,
            kerberos: needs ? (kerberos ? .ready : .impossible) : .notNeeded, at: now)
    }

    /// A method set by the user is the only one offered, nothing is remembered; NLA without
    /// Kerberos is no plan (the app says why).
    @Test func explicitMethods() {
        #expect(plan(.nla)?.arguments == [Self.nla])
        #expect(plan(.nla, kerberos: false) == nil)
        #expect(plan(.tls)?.arguments == ["/sec:tls"])
        #expect(plan(.rdp)?.arguments == ["/sec:rdp"])
        #expect(plan(.rdp, remembered: .nla) == SecurityPlan(arguments: ["/sec:rdp"]))
        #expect(plan(.tls)?.remembersOutcome == false)
    }

    /// Automatic: the computer chooses and the choice is remembered; without Kerberos NLA is not offered.
    @Test func automaticLetsTheComputerChoose() {
        #expect(plan(.automatic) == SecurityPlan(arguments: [], remembersOutcome: true))
        #expect(
            plan(.automatic, kerberos: false)
                == SecurityPlan(arguments: ["/sec:nla:off,ext:off"], remembersOutcome: true))
        // NLA failed before: not offered, and the plan says so.
        #expect(
            plan(.automatic, nlaFailed: true)
                == SecurityPlan(arguments: ["/sec:nla:off,ext:off"], remembersOutcome: true, withholdsFailedNLA: true))
    }

    /// Automatic with a remembered method: only that one, so the computer cannot be made weaker
    /// unnoticed.
    @Test func automaticUsesWhatItRemembered() {
        #expect(plan(.automatic, remembered: .rdp, age: 3600) == SecurityPlan(arguments: ["/sec:rdp"], floor: .rdp))
        #expect(plan(.automatic, remembered: .tls, age: 3600) == SecurityPlan(arguments: ["/sec:tls"], floor: .tls))
        #expect(plan(.automatic, remembered: .nla, age: 3600) == SecurityPlan(arguments: [Self.nla], floor: .nla))
        // TLS remembered: Kerberos is not looked up, and not needed.
        #expect(plan(.automatic, remembered: .tls, kerberos: false)?.arguments == ["/sec:tls"])
    }

    /// After a month the computer chooses again, but never weaker than what it accepted.
    @Test func afterAMonthOnlyStronger() {
        let month = RememberedSecurity.validity
        #expect(
            plan(.automatic, remembered: .rdp, age: month)
                == SecurityPlan(arguments: [], floor: .rdp, remembersOutcome: true))
        #expect(
            plan(.automatic, remembered: .tls, age: month)
                == SecurityPlan(arguments: ["/sec:rdp:off"], floor: .tls, remembersOutcome: true))
        #expect(plan(.automatic, remembered: .tls, age: month, kerberos: false)?.arguments == ["/sec:tls"])
        #expect(
            plan(.automatic, remembered: .nla, age: month)
                == SecurityPlan(arguments: [Self.nla], floor: .nla, remembersOutcome: true))
        // A date in the future (clock changed) is not trusted.
        #expect(plan(.automatic, remembered: .rdp, age: -3600)?.remembersOutcome == true)
    }

    /// The root CA not found yet (e.g. downloadable only on the organization's network): what the
    /// computer chooses is only the weakest allowed, the next attempt offers NLA again.
    @Test func rootCANotFoundYet() throws {
        let waiting = try #require(
            SecurityPlan.make(.automatic, remembered: nil, nlaFailed: false, kerberos: .missingAnchor, at: now))
        #expect(waiting.arguments == ["/sec:nla:off,ext:off"] && waiting.retriesNLA)
        let tls = waiting.remembering(.tls, at: now)
        #expect(tls.method == .tls && !tls.isCurrent(at: now))
        #expect(
            plan(.automatic, remembered: .tls, age: now.timeIntervalSince(tls.date))?.arguments == ["/sec:rdp:off"])
        // Otherwise the choice is remembered for a month.
        #expect(try #require(plan(.automatic)).remembering(.tls, at: now).isCurrent(at: now))
        #expect(waiting.remembering(.nla, at: now).isCurrent(at: now))
        // The computer requires NLA: the next attempt looks for the root CA again.
        #expect(waiting.requiresNLAWithoutAnchor(after: .securityRefused))
        #expect(!(try #require(plan(.automatic))).requiresNLAWithoutAnchor(after: .securityRefused))
        // Without a domain (no realm) NLA is not waited for.
        #expect(plan(.automatic, kerberos: false)?.retriesNLA == false)
    }

    /// NLA remembered, Kerberos not possible now (e.g. the root CA not downloaded yet): no plan,
    /// never a weaker method in its place.
    @Test func rememberedNLAWithoutKerberos() {
        #expect(plan(.automatic, remembered: .nla, kerberos: false) == nil)
        #expect(plan(.automatic, remembered: .nla, age: RememberedSecurity.validity, kerberos: false) == nil)
        // A failed NLA never withholds a remembered one.
        #expect(plan(.automatic, remembered: .nla, nlaFailed: true)?.arguments == [Self.nla])
    }

    /// Kerberos (the root CA lookup) only where NLA may be used.
    @Test func kerberosOnlyWhereNLAMayBeUsed() {
        func needs(
            _ security: ConnectionSecurity, _ remembered: SecurityMethod?, age: TimeInterval = 0, failed: Bool = false
        ) -> Bool {
            SecurityPlan.needsKerberos(
                security, remembered: remembered.map { RememberedSecurity(method: $0, date: now - age) },
                nlaFailed: failed, at: now)
        }
        #expect(needs(.nla, nil) && !needs(.tls, nil) && !needs(.rdp, nil))
        #expect(needs(.automatic, nil) && !needs(.automatic, nil, failed: true))
        #expect(!needs(.automatic, .tls) && needs(.automatic, .tls, age: RememberedSecurity.validity))
        #expect(needs(.automatic, .nla) && needs(.automatic, .nla, failed: true))
        // Without a domain or gateway not for automatic (nothing looked up); NLA set by the user says why.
        #expect(!SecurityPlan.needsKerberos(.automatic, remembered: nil, nlaFailed: false, nlaPossible: false, at: now))
        #expect(SecurityPlan.needsKerberos(.nla, remembered: nil, nlaFailed: false, nlaPossible: false, at: now))
    }

    /// What a failure changes in the memory.
    @Test func outcomes() throws {
        let rdp = try #require(plan(.automatic, remembered: .rdp))
        let tls = try #require(plan(.automatic, remembered: .tls))
        let choose = try #require(plan(.automatic))
        let tlsOrStronger = try #require(plan(.automatic, remembered: .tls, age: RememberedSecurity.validity))
        let nla = try #require(plan(.automatic, remembered: .nla))
        // The computer requires stronger security now: it chooses again (never weaker than TLS).
        #expect(tls.outcome(of: .securityRefused) == .letComputerChooseAgain)
        #expect(rdp.outcome(of: .computerUnreachable) == .letComputerChooseAgain)
        #expect(tls.outcome(of: .computerUnreachable) == .keep)
        // Said in the message: the next attempt tries stronger security.
        #expect(rdp.mayRequireStrongerSecurity(after: .computerUnreachable))
        #expect(!tls.mayRequireStrongerSecurity(after: .computerUnreachable))
        #expect(!choose.mayRequireStrongerSecurity(after: .computerUnreachable))
        #expect(nla.outcome(of: .kerberosFailed) == .keep, "NLA known to work is never switched off")
        #expect(choose.outcome(of: .kerberosFailed) == .rememberNLAFailed)
        #expect(tlsOrStronger.outcome(of: .kerberosFailed) == .rememberNLAFailed)
        #expect(try #require(plan(.nla)).outcome(of: .kerberosFailed) == .keep)
        #expect(choose.outcome(of: .securityRefused) == .keep)
        // Weaker security only with the user's consent.
        #expect(tls.isWeakened(by: .computerOffersOnlyWeakerSecurity))
        #expect(tlsOrStronger.isWeakened(by: .computerOffersOnlyWeakerSecurity))
        #expect(!rdp.isWeakened(by: .computerOffersOnlyWeakerSecurity))
        #expect(!choose.isWeakened(by: .computerOffersOnlyWeakerSecurity))
    }

    /// The computer requires NLA after it failed: the same answer each time (no alternating), the
    /// user decides to try it again.
    @Test func failedNLARequiredByTheComputer() throws {
        let withheld = try #require(plan(.automatic, nlaFailed: true))
        #expect(withheld.requiresWithheldNLA(after: .securityRefused))
        #expect(withheld.outcome(of: .securityRefused) == .keep)
        #expect(!(try #require(plan(.automatic, kerberos: false))).requiresWithheldNLA(after: .securityRefused))
    }

    @Test func methodsOrderedByStrength() {
        #expect(SecurityMethod.rdp < .tls && SecurityMethod.tls < .nla)
        #expect(SecurityMethod(negotiatedProtocol: "HYBRID_EX") == .nla)
        #expect(SecurityMethod(negotiatedProtocol: "HYBRID") == .nla)
        #expect(SecurityMethod(negotiatedProtocol: "SSL") == .tls)
        #expect(SecurityMethod(negotiatedProtocol: "RDP") == .rdp)
        #expect(SecurityMethod(negotiatedProtocol: "AAD") == nil)
    }

    /// The realm is the computer's domain; none for a name without a domain or an IP address.
    @Test(
        arguments: [
            ("pc.corp.example", "CORP.EXAMPLE"), ("PC.Sub.Corp.Example", "SUB.CORP.EXAMPLE"),
            ("pc.corp.example:3390", "CORP.EXAMPLE"),
            ("pc", nil), ("192.0.2.10", nil), ("[2001:db8::1]", nil),
        ] as [(String, String?)])
    func realm(computer: String, realm: String?) throws {
        #expect(kerberosRealm(of: try HostAddress(parsing: computer)) == realm)
    }

    /// Remembered per profile and computer; another computer starts over.
    @Test func memoryPerProfileAndComputer() throws {
        let suite = "cardgate-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = SecurityMemory(defaults: defaults)
        var profile = ConnectionProfile(name: "x", computer: try HostAddress(parsing: "pc.corp.example"))
        let other = ConnectionProfile(name: "y", computer: try HostAddress(parsing: "pc.corp.example"))
        #expect(memory.remembered(for: profile) == nil)
        memory.remember(RememberedSecurity(method: .nla, date: now), for: profile)
        #expect(memory.remembered(for: profile) == RememberedSecurity(method: .nla, date: now))
        #expect(memory.remembered(for: other) == nil)
        memory.remember(RememberedSecurity(method: .tls, date: now), for: other)

        let old = profile
        profile.computer = try HostAddress(parsing: "pc2.corp.example")
        #expect(memory.remembered(for: profile) == nil, "another computer starts over")
        memory.keepOnly([profile, other])
        profile.computer = old.computer
        #expect(memory.remembered(for: profile) == nil, "the old computer's entry is dropped")

        // Choose again: TLS stays the weakest allowed.
        memory.letComputerChooseAgain(for: other)
        let again = try #require(memory.remembered(for: other))
        #expect(again.method == .tls && !again.isCurrent(at: now))
        memory.keepOnly([])
        #expect(memory.remembered(for: other) == nil)
    }

    /// NLA that failed with automatic security, for a month and per gateway.
    @Test func failedNLAPerGateway() throws {
        let suite = "cardgate-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = SecurityMemory(defaults: defaults)
        var profile = ConnectionProfile(
            name: "x", computer: try HostAddress(parsing: "pc.corp.example"),
            gateway: try HostAddress(parsing: "gw.example.com"))
        #expect(!memory.nlaRecentlyFailed(for: profile, at: now))
        memory.rememberNLAFailed(for: profile, at: now)
        #expect(memory.nlaRecentlyFailed(for: profile, at: now + 3600))
        #expect(memory.nlaRecentlyFailed(for: profile, at: now + 6 * 24 * 3600))
        #expect(!memory.nlaRecentlyFailed(for: profile, at: now + SecurityMemory.nlaFailedValidity))
        memory.keepOnly([profile])
        #expect(memory.nlaRecentlyFailed(for: profile, at: now), "kept for an existing connection")

        let gateway = profile.gateway
        profile.gateway = try HostAddress(parsing: "gw2.example.com")
        #expect(!memory.nlaRecentlyFailed(for: profile, at: now), "another gateway may have a KDC proxy")
        profile.gateway = gateway
        memory.forgetNLAFailed(for: profile)
        #expect(!memory.nlaRecentlyFailed(for: profile, at: now))
        memory.rememberNLAFailed(for: profile, at: now)
        memory.forget(for: profile)
        #expect(!memory.nlaRecentlyFailed(for: profile, at: now))
    }

    /// The result when it comes in time, the fallback when it does not.
    @Test func timeout() async {
        #expect(await withTimeout(.seconds(5), fallback: 0) { 1 } == 1)
        #expect(
            await withTimeout(.milliseconds(50), fallback: 0) {
                Thread.sleep(forTimeInterval: 1); return 1
            } == 0)
    }

    /// Root CAs found once are kept (by card certificate).
    @Test func anchorsKept() throws {
        let suite = "cardgate-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = SecurityMemory(defaults: defaults)
        #expect(memory.anchor(forCertificate: "AB12") == nil)
        memory.rememberAnchor(Data([1, 2]), forCertificate: "AB12")
        memory.keepOnly([])
        #expect(memory.anchor(forCertificate: "ab12") == Data([1, 2]))
        // At most ten: older cards go.
        for index in 0..<SecurityMemory.maximumAnchors { memory.rememberAnchor(Data([3]), forCertificate: "c\(index)") }
        #expect(memory.anchor(forCertificate: "ab12") == nil)
        #expect(memory.anchor(forCertificate: "c9") == Data([3]))
        memory.forgetAnchors()
        #expect(memory.anchor(forCertificate: "c9") == nil)
    }

    /// With test data (UI tests, screenshots) the user's memory is never used.
    @Test func testDataHasItsOwnMemory() throws {
        let profile = ConnectionProfile(name: "x", computer: try HostAddress(parsing: "pc.corp.example"))
        defer { UserDefaults.standard.removePersistentDomain(forName: SecurityMemory.testSuite) }
        let memory = SecurityMemory.standard(environment: [AppDirectories.dataDirectoryVariable: "/tmp/x"])
        memory.remember(RememberedSecurity(method: .rdp, date: now), for: profile)
        #expect(SecurityMemory(defaults: .standard).remembered(for: profile) == nil)
        #expect(SecurityMemory.standard(environment: [:]).remembered(for: profile) == nil)
        #expect(
            SecurityMemory.standard(environment: [AppDirectories.dataDirectoryVariable: "/tmp/x"])
                .remembered(for: profile) == nil, "empty at each launch")
    }

    /// Saved profiles from before the setting existed use automatic.
    @Test func olderProfilesUseAutomatic() throws {
        let json = #"{"id":"6F1D2C3B-4A59-4C68-8E7F-1A2B3C4D5E6F","name":"x","computer":"pc.corp.example"}"#
        let profile = try JSONDecoder().decode(ConnectionProfile.self, from: Data(json.utf8))
        #expect(profile.security == .automatic)
        var nla = profile
        nla.security = .nla
        let saved = try JSONDecoder().decode(ConnectionProfile.self, from: try JSONEncoder().encode(nla))
        #expect(saved.security == .nla)

        // A method from a newer version: automatic, the profile is kept.
        let newer = json.replacingOccurrences(of: "}", with: #","security":"aad"}"#)
        #expect(try JSONDecoder().decode(ConnectionProfile.self, from: Data(newer.utf8)).security == .automatic)
    }
}

/// The root CA for PKINIT: certificates made at run time (none are kept in the repository).
struct PKINITAnchorTests {
    /// Makes a root CA, a user certificate it issued and another root, with the system's openssl.
    struct Made {
        var root: SecCertificate
        var other: SecCertificate
        var user: SecCertificate
    }

    static func certificates() throws -> Made {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cardgate-ca-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        func openssl(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(filePath: "/usr/bin/openssl")
            process.arguments = arguments
            process.currentDirectoryURL = directory
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 { throw CocoaError(.executableLoad) }
        }
        // Its own configuration: the system's LibreSSL has none with CA extensions.
        let config = """
            [req]
            distinguished_name = dn
            [dn]
            [ca]
            basicConstraints = critical,CA:TRUE
            keyUsage = critical,keyCertSign,cRLSign
            [user]
            basicConstraints = CA:FALSE
            keyUsage = critical,digitalSignature
            """
        try Data(config.utf8).write(to: directory.appending(path: "openssl.cnf"))
        for name in ["root", "other"] {
            try openssl(
                [
                    "req", "-config", "openssl.cnf", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "\(name).key",
                    "-out", "\(name).pem", "-days", "3650", "-subj", "/CN=Example \(name) CA", "-extensions", "ca",
                ])
        }
        try openssl(
            [
                "req", "-config", "openssl.cnf", "-newkey", "rsa:2048", "-nodes", "-keyout", "user.key",
                "-out", "user.csr", "-subj", "/CN=User Example",
            ])
        try openssl(
            [
                "x509", "-req", "-in", "user.csr", "-CA", "root.pem", "-CAkey", "root.key", "-CAcreateserial",
                "-out", "user.pem", "-days", "365", "-extfile", "openssl.cnf", "-extensions", "user",
            ])
        func load(_ name: String) throws -> SecCertificate {
            let pem = try String(contentsOf: directory.appending(path: "\(name).pem"), encoding: .utf8)
            let base64 = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
            let der = try #require(Data(base64Encoded: base64))
            return try #require(SecCertificateCreateWithData(nil, der as CFData))
        }
        return Made(root: try load("root"), other: try load("other"), user: try load("user"))
    }

    /// The user certificate verifies to the root that issued it, never to another one.
    @Test func verifiesOnlyToItsIssuer() throws {
        let made = try Self.certificates()
        #expect(PKINITAnchor.isSelfSigned(made.root))
        #expect(!PKINITAnchor.isSelfSigned(made.user))
        #expect(PKINITAnchor.verifies(made.user, intermediates: [], root: made.root))
        #expect(!PKINITAnchor.verifies(made.user, intermediates: [], root: made.other))
    }

    /// Without the issuer (no AIA address in it, not on this Mac) there is no root.
    @Test func noRootWithoutTheChain() throws {
        let made = try Self.certificates()
        #expect(PKINITAnchor.findRoot(of: SecCertificateCopyData(made.user) as Data) == nil)
    }

    @Test func pemForKerberos() {
        let pem = PKINITAnchor.pem(Data(repeating: 0xAB, count: 60))
        #expect(pem.hasPrefix("-----BEGIN CERTIFICATE-----\n"))
        #expect(pem.hasSuffix("\n-----END CERTIFICATE-----\n"))
        #expect(pem.split(separator: "\n").allSatisfy { $0.count <= 64 })
    }
}
