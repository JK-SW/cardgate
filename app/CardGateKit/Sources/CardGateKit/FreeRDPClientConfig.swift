public import Foundation

/// Private configuration directory of the bundled FreeRDP client.
///
/// FreeRDP reads `$XDG_CONFIG_HOME/freerdp/sdl-freerdp.json` and keeps its certificate store
/// there. CardGate points `XDG_CONFIG_HOME` to its own directory so the user's own FreeRDP
/// setup is neither used nor modified. The client's Kerberos configuration (`krb5.conf`,
/// `KRB5_CONFIG`) is there too, so that of the Mac is not used either.
public struct FreeRDPClientConfig: Sendable {
    /// Value for `XDG_CONFIG_HOME`.
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// `~/Library/Application Support/CardGate/FreeRDP`
    public static func standard() throws -> FreeRDPClientConfig {
        FreeRDPClientConfig(directory: try AppDirectories.data().appending(path: "FreeRDP"))
    }

    public var sdlConfigURL: URL { directory.appending(path: "freerdp/sdl-freerdp.json") }

    /// The client's Kerberos configuration (`KRB5_CONFIG`).
    public var kerberosConfigURL: URL { directory.appending(path: "krb5.conf") }

    /// A link to the app's Kerberos plugins. `krb5.conf` names the link, not the app: libkrb5
    /// expands `%{…}` in the plugin path and has no escape for it, and the app may be anywhere.
    public var kerberosPluginsLink: URL { directory.appending(path: "krb5-plugins") }

    /// The root certification authority Kerberos trusts for the domain controller (`PKINITAnchor`).
    public var kerberosAnchorURL: URL { directory.appending(path: "pkinit-anchor.pem") }

    public enum InstallError: Error, Equatable {
        /// The configuration directory contains `%{`, which libkrb5 would expand.
        case unusableDirectory
    }

    /// Contents of `krb5.conf`: the plugins come from the app (libkrb5 would look in the
    /// directory it was built for), nothing is looked up in DNS. With a realm (`KerberosSetup`)
    /// its KDC is the gateway's KDC proxy and PKINIT trusts only `anchor` for the domain
    /// controller, whose certificate names the domain (Active Directory's KDC certificates do).
    static func kerberosConfig(plugins: URL, realm: KerberosSetup.Realm?, anchor: URL) -> String {
        var text = """
            # Written by CardGate for its remote desktop client; not the Kerberos setup of this Mac.
            [libdefaults]

            """
        if let realm { text += "  default_realm = \(realm.name)\n" }
        text += """
              plugin_base_dir = \(profileString(plugins.path(percentEncoded: false)))
              dns_lookup_kdc = false
              dns_lookup_realm = false
              dns_canonicalize_hostname = false
              rdns = false

            """
        if let realm {
            let domain = realm.name.lowercased()
            // EKU: Windows domain controller certificates have KDC Authentication, those of older
            // templates only Server Authentication (MIT's setting for Windows KDCs).
            text += """
                [realms]
                  \(realm.name) = {
                    kdc = \(profileString("https://\(realm.kdcProxy)/KdcProxy"))
                    pkinit_anchors = \(profileString("FILE:" + anchor.path(percentEncoded: false)))
                    pkinit_kdc_hostname = \(domain)
                    pkinit_eku_checking = kpServerAuth
                  }

                [domain_realm]
                  .\(domain) = \(realm.name)
                  \(domain) = \(realm.name)

                """
        }
        return text
    }

    /// A value in the krb5 profile syntax: quoted, with backslash, quote and line breaks escaped.
    static func profileString(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"" + escaped + "\""
    }

    /// Contents of `sdl-freerdp.json`.
    struct SDLConfig: Codable, Equatable {
        /// Client hotkeys (fullscreen, disconnect, …) need Left Control + Left Option + Left Shift.
        /// FreeRDP's default (Right Shift alone) disconnects the session when typing a capital D.
        var hotkeyModifiers = ["KMOD_LCTRL", "KMOD_LALT", "KMOD_LSHIFT"]
        /// `true` keeps the macOS scroll direction instead of converting it to the Windows one.
        var useLocalMouseScrollDirection: Bool

        enum CodingKeys: String, CodingKey {
            case hotkeyModifiers = "SDL_KeyModMask"
            case useLocalMouseScrollDirection = "UseLocalMouseScrollDirection"
        }
    }

    /// Writes the client configuration for the next connection (the files are owned by CardGate).
    public func install(for profile: ConnectionProfile, kerberos: KerberosSetup) throws {
        guard !kerberosPluginsLink.path(percentEncoded: false).contains("%{") else {
            throw InstallError.unusableDirectory
        }
        let config = SDLConfig(useLocalMouseScrollDirection: profile.input.scrollLikeThisMac)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: sdlConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(config).write(to: sdlConfigURL, options: .atomic)
        // The link points to this copy of the app, wherever it is now.
        let fileManager = FileManager.default
        if (try? fileManager.destinationOfSymbolicLink(atPath: kerberosPluginsLink.path(percentEncoded: false))) != nil
            || fileManager.fileExists(atPath: kerberosPluginsLink.path(percentEncoded: false))
        {
            try fileManager.removeItem(at: kerberosPluginsLink)
        }
        try fileManager.createSymbolicLink(at: kerberosPluginsLink, withDestinationURL: kerberos.plugins)
        if let anchor = kerberos.anchor {
            try Data(PKINITAnchor.pem(anchor).utf8).write(to: kerberosAnchorURL, options: .atomic)
        } else if fileManager.fileExists(atPath: kerberosAnchorURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: kerberosAnchorURL)
        }
        let kerberosConfig = Self.kerberosConfig(
            plugins: kerberosPluginsLink, realm: kerberos.realm, anchor: kerberosAnchorURL)
        try Data(kerberosConfig.utf8).write(to: kerberosConfigURL, options: .atomic)
    }
}

/// What the client needs for network level authentication with the card: Kerberos with PKINIT
/// through the gateway's KDC proxy.
public struct KerberosSetup: Equatable, Sendable {
    /// The app's Kerberos plugins (`FreeRDPCommand.kerberosPlugins(in:)`).
    public var plugins: URL
    /// The root certification authority of the card certificate (`PKINITAnchor`).
    public var anchor: Data?
    /// The realm and its KDC; `nil` when NLA is not possible (see `isUsable`).
    public var realm: Realm?
    /// NLA would be possible with the root of the card certificate, which was not found (yet: it is
    /// downloaded, e.g. only on the organization's network).
    public var waitsForAnchor: Bool

    public struct Realm: Equatable, Sendable {
        /// The computer's domain in upper case (`kerberosRealm(of:)`).
        public var name: String
        /// The gateway; its KDC proxy is `https://<gateway>/KdcProxy` (Windows' KDC proxy server).
        public var kdcProxy: HostAddress
    }

    /// - Parameters:
    ///   - computer: the realm is its domain.
    ///   - gateway: its KDC proxy reaches the domain controllers.
    public init(plugins: URL, computer: HostAddress, gateway: HostAddress?, anchor: Data?) {
        self.plugins = plugins
        self.anchor = anchor
        let name = gateway == nil ? nil : kerberosRealm(of: computer)
        if let gateway, anchor != nil, let name {
            realm = Realm(name: name, kdcProxy: gateway)
        }
        waitsForAnchor = name != nil && anchor == nil
    }

    /// NLA can be offered: the computer has a domain, there is a gateway and the root of the card
    /// certificate is known.
    public var isUsable: Bool { realm != nil }
}
