import CardGateKit
import Foundation
import Testing

struct FreeRDPClientConfigTests {
    struct Written: Decodable, Equatable {
        var hotkeyModifiers: [String]
        var useLocalMouseScrollDirection: Bool

        enum CodingKeys: String, CodingKey {
            case hotkeyModifiers = "SDL_KeyModMask"
            case useLocalMouseScrollDirection = "UseLocalMouseScrollDirection"
        }
    }

    func install(scrollLikeThisMac: Bool) throws -> Written {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cardgate-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = FreeRDPClientConfig(directory: directory)
        var profile = ConnectionProfile(name: "x", computer: try HostAddress(parsing: "pc.example.com"))
        profile.input.scrollLikeThisMac = scrollLikeThisMac
        try config.install(for: profile)
        try config.install(for: profile)  // overwrites
        #expect(config.sdlConfigURL == directory.appending(path: "freerdp/sdl-freerdp.json"))
        return try JSONDecoder().decode(Written.self, from: Data(contentsOf: config.sdlConfigURL))
    }

    @Test func safeHotkeys() throws {
        #expect(try install(scrollLikeThisMac: true).hotkeyModifiers == ["KMOD_LCTRL", "KMOD_LALT", "KMOD_LSHIFT"])
    }

    @Test func scrollDirection() throws {
        #expect(try install(scrollLikeThisMac: true).useLocalMouseScrollDirection)
        #expect(try !install(scrollLikeThisMac: false).useLocalMouseScrollDirection)
    }
}
