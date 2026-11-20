import Foundation
import Testing

@testable import CardGateKit

struct FreeRDPClientConfigTests {
    struct Written: Decodable, Equatable {
        var hotkeyModifiers: [String]
        var useLocalMouseScrollDirection: Bool

        enum CodingKeys: String, CodingKey {
            case hotkeyModifiers = "SDL_KeyModMask"
            case useLocalMouseScrollDirection = "UseLocalMouseScrollDirection"
        }
    }

    static let plugins = URL(filePath: "/Applications/CardGate.app/Contents/PlugIns/krb5")
    static func computer() throws -> HostAddress { try HostAddress(parsing: "pc.corp.example") }
    static func kerberos(plugins: URL = plugins, gateway: HostAddress? = nil, anchor: Data? = nil) throws
        -> KerberosSetup
    {
        KerberosSetup(plugins: plugins, computer: try computer(), gateway: gateway, anchor: anchor)
    }

    func install(scrollLikeThisMac: Bool) throws -> Written {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cardgate-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = FreeRDPClientConfig(directory: directory)
        var profile = ConnectionProfile(name: "x", computer: try HostAddress(parsing: "pc.example.com"))
        profile.input.scrollLikeThisMac = scrollLikeThisMac
        try config.install(for: profile, kerberos: try Self.kerberos())
        try config.install(for: profile, kerberos: try Self.kerberos())  // overwrites
        #expect(config.sdlConfigURL == directory.appending(path: "freerdp/sdl-freerdp.json"))
        return try JSONDecoder().decode(Written.self, from: Data(contentsOf: config.sdlConfigURL))
    }

    @Test func safeHotkeys() throws {
        #expect(try install(scrollLikeThisMac: true).hotkeyModifiers == ["KMOD_LCTRL", "KMOD_LALT", "KMOD_LSHIFT"])
    }

    /// Kerberos uses only CardGate's settings: its plugins from the app, no DNS lookups.
    @Test func kerberosConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cardgate-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = FreeRDPClientConfig(directory: directory)
        try config.install(
            for: ConnectionProfile(name: "x", computer: try HostAddress(parsing: "pc.example.com")),
            kerberos: try Self.kerberos())
        #expect(config.kerberosConfigURL == directory.appending(path: "krb5.conf"))
        let written = try String(contentsOf: config.kerberosConfigURL, encoding: .utf8)
        let lines = written.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains("[libdefaults]"))
        // The plugins through a link in CardGate's folder (the app's path may contain %{…}).
        let link = config.kerberosPluginsLink.path(percentEncoded: false)
        #expect(lines.contains("plugin_base_dir = \"\(link)\""))
        let target = try FileManager.default.destinationOfSymbolicLink(atPath: link)
        #expect(target == Self.plugins.path(percentEncoded: false))
        #expect(lines.contains("dns_lookup_kdc = false"))
        #expect(lines.contains("dns_lookup_realm = false"))
    }

    /// The link follows the app when it moved; a folder libkrb5 would expand is refused.
    @Test func kerberosPluginsLinkFollowsTheApp() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cardgate-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = FreeRDPClientConfig(directory: directory)
        let profile = ConnectionProfile(name: "x", computer: try HostAddress(parsing: "pc.example.com"))
        try config.install(for: profile, kerberos: try Self.kerberos())
        let moved = URL(filePath: "/Users/test/Apps/%{TEMP}/CardGate.app/Contents/PlugIns/krb5")
        try config.install(for: profile, kerberos: try Self.kerberos(plugins: moved))
        let link = config.kerberosPluginsLink.path(percentEncoded: false)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link) == moved.path(percentEncoded: false))

        let odd = FreeRDPClientConfig(directory: directory.appending(path: "%{TEMP}"))
        #expect(throws: FreeRDPClientConfig.InstallError.unusableDirectory) {
            try odd.install(for: profile, kerberos: try Self.kerberos())
        }
    }

    /// With a realm: its KDC is the gateway's KDC proxy, PKINIT trusts only the card's root CA and
    /// accepts the domain controller of the domain.
    @Test func kerberosRealmThroughTheGateway() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cardgate-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = FreeRDPClientConfig(directory: directory)
        let anchor = Data([0x30, 0x03, 0x02, 0x01, 0x01])
        let setup = try Self.kerberos(gateway: try HostAddress(parsing: "gw.example.com"), anchor: anchor)
        #expect(setup.isUsable)
        try config.install(for: ConnectionProfile(name: "x", computer: try Self.computer()), kerberos: setup)
        let written = try String(contentsOf: config.kerberosConfigURL, encoding: .utf8)
        let lines = written.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.contains("default_realm = CORP.EXAMPLE"))
        #expect(lines.contains("CORP.EXAMPLE = {"))
        #expect(lines.contains(#"kdc = "https://gw.example.com/KdcProxy""#))
        #expect(lines.contains("pkinit_anchors = \"FILE:\(config.kerberosAnchorURL.path(percentEncoded: false))\""))
        #expect(lines.contains("pkinit_kdc_hostname = corp.example"))
        #expect(lines.contains("pkinit_eku_checking = kpServerAuth"))
        // The default realm belongs to [libdefaults], before the other sections.
        let realmLine = try #require(lines.firstIndex(of: "default_realm = CORP.EXAMPLE"))
        let libdefaults = try #require(lines.firstIndex(of: "[libdefaults]"))
        let realms = try #require(lines.firstIndex(of: "[realms]"))
        #expect(libdefaults < realmLine && realmLine < realms)
        #expect(lines.contains(".corp.example = CORP.EXAMPLE"))
        let pem = try String(contentsOf: config.kerberosAnchorURL, encoding: .utf8)
        #expect(pem == PKINITAnchor.pem(anchor))

        // Without the root CA no realm (NLA is not offered) and no stale anchor file.
        let without = try Self.kerberos(gateway: try HostAddress(parsing: "gw.example.com"))
        #expect(!without.isUsable && without.waitsForAnchor)
        #expect(!(try Self.kerberos()).waitsForAnchor, "no gateway, no KDC proxy")
        try config.install(for: ConnectionProfile(name: "x", computer: try Self.computer()), kerberos: without)
        #expect(!FileManager.default.fileExists(atPath: config.kerberosAnchorURL.path(percentEncoded: false)))
        let plain = try String(contentsOf: config.kerberosConfigURL, encoding: .utf8)
        #expect(!plain.contains("[realms]") && !plain.contains("default_realm") && plain.contains("plugin_base_dir"))
    }

    /// A folder with a quote, backslash or line break in its name still gives one value.
    @Test func kerberosPathIsQuoted() {
        #expect(FreeRDPClientConfig.profileString(#"/Users/a "b"\c"#) == #""/Users/a \"b\"\\c""#)
        #expect(FreeRDPClientConfig.profileString("/x\ny\tz") == #""/x\ny\tz""#)
    }

    @Test func scrollDirection() throws {
        #expect(try install(scrollLikeThisMac: true).useLocalMouseScrollDirection)
        #expect(try !install(scrollLikeThisMac: false).useLocalMouseScrollDirection)
    }
}
