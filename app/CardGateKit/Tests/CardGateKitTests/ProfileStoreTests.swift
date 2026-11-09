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
