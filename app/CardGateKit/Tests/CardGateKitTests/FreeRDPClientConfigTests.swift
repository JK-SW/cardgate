import CardGateKit
import Foundation
import Testing

struct FreeRDPClientConfigTests {
    @Test func installsHotkeyConfiguration() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cardgate-config-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let config = FreeRDPClientConfig(directory: directory)
        try config.install()
        try config.install()  // idempotent

        #expect(config.sdlConfigURL == directory.appending(path: "freerdp/sdl-freerdp.json"))
        let json = try JSONDecoder().decode([String: [String]].self, from: Data(contentsOf: config.sdlConfigURL))
        #expect(json == ["SDL_KeyModMask": ["KMOD_LCTRL", "KMOD_LALT", "KMOD_LSHIFT"]])
    }
}
