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

    func install(scrollLikeThisMac: Bool) throws -> Written {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cardgate-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = FreeRDPClientConfig(directory: directory)
        var profile = ConnectionProfile(name: "x", computer: try HostAddress(parsing: "pc.example.com"))
        profile.input.scrollLikeThisMac = scrollLikeThisMac
        try config.install(for: profile, kerberosPlugins: Self.plugins)
        try config.install(for: profile, kerberosPlugins: Self.plugins)  // overwrites
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
            kerberosPlugins: Self.plugins)
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
        try config.install(for: profile, kerberosPlugins: Self.plugins)
        let moved = URL(filePath: "/Users/test/Apps/%{TEMP}/CardGate.app/Contents/PlugIns/krb5")
        try config.install(for: profile, kerberosPlugins: moved)
        let link = config.kerberosPluginsLink.path(percentEncoded: false)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link) == moved.path(percentEncoded: false))

        let odd = FreeRDPClientConfig(directory: directory.appending(path: "%{TEMP}"))
        #expect(throws: FreeRDPClientConfig.InstallError.unusableDirectory) {
            try odd.install(for: profile, kerberosPlugins: Self.plugins)
        }
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
