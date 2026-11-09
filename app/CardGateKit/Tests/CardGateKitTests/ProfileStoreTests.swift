import CardGateKit
import Foundation
import Testing

struct ProfileStoreTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "cardgate-tests-\(UUID().uuidString)")

    var store: ProfileStore { ProfileStore(fileURL: directory.appending(path: "nested/profiles.json")) }

    @Test func missingFileMeansNoProfiles() throws {
        let loaded = try store.load()
        #expect(loaded.profiles.isEmpty)
        #expect(loaded.selectedID == nil)
    }

    @Test func savesAndLoads() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let profiles = [
            ConnectionProfile(
                name: "Office", computer: try HostAddress(parsing: "pc01.corp.example"),
                gateway: try HostAddress(parsing: "rdg.example.com"),
                display: .init(mode: .window, windowSize: .init(width: 1440, height: 900))),
            ConnectionProfile(
                name: "Lab", computer: try HostAddress(parsing: "10.0.0.5:3390"),
                pkcs11Module: "/opt/module.dylib", redirection: .init(clipboard: false, audio: false)),
        ]
        try store.save(profiles: profiles, selectedID: profiles[1].id)
        let loaded = try store.load()
        #expect(loaded.profiles == profiles)
        #expect(loaded.selectedID == profiles[1].id)
    }

    @Test func corruptFileThrows() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(throws: (any Error).self) { try store.load() }
    }
}

struct ProfileCompatibilityTests {
    /// Profiles saved by the first version have no `input` settings.
    @Test func loadsProfilesWithoutNewerSettings() throws {
        let json = """
            {"id":"6F1C2A52-8B39-4B79-9A43-2B7D4D0B5E10","name":"Office","computer":"pc01.corp.example",
             "display":{"mode":"window"},"redirection":{"clipboard":true,"audio":false}}
            """
        let profile = try JSONDecoder().decode(ConnectionProfile.self, from: Data(json.utf8))
        #expect(profile.name == "Office")
        #expect(profile.gateway == nil)
        #expect(!profile.redirection.audio)
        #expect(profile.input == InputSettings())
    }
}
