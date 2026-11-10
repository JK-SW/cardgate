public import Foundation

/// Private configuration directory of the bundled FreeRDP client.
///
/// FreeRDP reads `$XDG_CONFIG_HOME/freerdp/sdl-freerdp.json` and keeps its certificate store
/// there. CardGate points `XDG_CONFIG_HOME` to its own directory so the user's own FreeRDP
/// setup is neither used nor modified.
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

    /// Writes the client configuration for the next connection (the file is owned by CardGate).
    public func install(for profile: ConnectionProfile) throws {
        let config = SDLConfig(useLocalMouseScrollDirection: profile.input.scrollLikeThisMac)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: sdlConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(config).write(to: sdlConfigURL, options: .atomic)
    }
}
