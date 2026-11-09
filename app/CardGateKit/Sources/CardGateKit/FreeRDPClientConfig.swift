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
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return FreeRDPClientConfig(directory: support.appending(path: "CardGate/FreeRDP"))
    }

    public var sdlConfigURL: URL { directory.appending(path: "freerdp/sdl-freerdp.json") }

    /// Client hotkeys (fullscreen, disconnect, …) need Left Control + Left Option + Left Shift.
    /// FreeRDP's default (Right Shift alone) disconnects the session when typing a capital D.
    static let sdlConfig: [String: [String]] = [
        "SDL_KeyModMask": ["KMOD_LCTRL", "KMOD_LALT", "KMOD_LSHIFT"]
    ]

    /// Writes the client configuration (overwrites the file each time; it is owned by CardGate).
    public func install() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(
            at: sdlConfigURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(Self.sdlConfig).write(to: sdlConfigURL, options: .atomic)
    }
}
