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

    public enum InstallError: Error, Equatable {
        /// The configuration directory contains `%{`, which libkrb5 would expand.
        case unusableDirectory
    }

    /// Contents of `krb5.conf`: the plugins come from the app (libkrb5 would look in the
    /// directory it was built for), nothing is looked up in DNS.
    static func kerberosConfig(plugins: URL) -> String {
        """
        # Written by CardGate for its remote desktop client; not the Kerberos setup of this Mac.
        [libdefaults]
          plugin_base_dir = \(profileString(plugins.path(percentEncoded: false)))
          dns_lookup_kdc = false
          dns_lookup_realm = false
          dns_canonicalize_hostname = false
          rdns = false

        """
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
    /// - Parameter kerberosPlugins: the app's Kerberos plugins (`FreeRDPCommand.kerberosPlugins(in:)`).
    public func install(for profile: ConnectionProfile, kerberosPlugins: URL) throws {
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
        try fileManager.createSymbolicLink(at: kerberosPluginsLink, withDestinationURL: kerberosPlugins)
        try Data(Self.kerberosConfig(plugins: kerberosPluginsLink).utf8).write(to: kerberosConfigURL, options: .atomic)
    }
}
