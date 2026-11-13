import CardGateKit
import Foundation
import Testing

struct ProfileStoreTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "cardgate-tests-\(UUID().uuidString)")

    var store: ProfileStore { ProfileStore(fileURL: directory.appending(path: "nested/profiles.json")) }

    func office() throws -> ConnectionProfile {
        ConnectionProfile(
            name: "Office", computer: try HostAddress(parsing: "pc01.corp.example"),
            gateway: try HostAddress(parsing: "rdg.example.com"))
    }

    func write(_ text: String) throws {
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: store.fileURL)
    }

    func backups() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: store.fileURL.deletingLastPathComponent(), includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("profiles.unreadable-") }
    }

    @Test func missingFileMeansNoProfiles() {
        let loaded = store.load()
        #expect(loaded == ProfileStore.Loaded())
        #expect(loaded.canSave)
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
        let loaded = store.load()
        #expect(loaded.profiles == profiles)
        #expect(loaded.selectedID == profiles[1].id)
        #expect(loaded.problem == nil && loaded.canSave)
    }

    /// A file that is not readable at all is moved aside before anything can overwrite it.
    @Test func unreadableFileIsMovedToABackup() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try write("not json")
        let loaded = store.load()
        #expect(loaded.profiles.isEmpty)
        guard case .unreadable(let backup) = loaded.problem else {
            Issue.record("expected a backup, got \(String(describing: loaded.problem))")
            return
        }
        #expect(loaded.canSave)
        #expect(try String(contentsOf: backup, encoding: .utf8) == "not json")
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path(percentEncoded: false)))

        try store.save(profiles: [office()], selectedID: nil)
        #expect(try String(contentsOf: backup, encoding: .utf8) == "not json", "the backup is kept")
    }

    /// One damaged profile (an address an older or newer version wrote differently, an unknown
    /// display mode) does not take the others with it; the file as it was is backed up.
    @Test func damagedProfileIsSkipped() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let good = try office()
        try store.save(profiles: [good], selectedID: good.id)
        var text = try String(contentsOf: store.fileURL, encoding: .utf8)
        let bad = #"{"id":"6F1C2A52-8B39-4B79-9A43-2B7D4D0B5E10","name":"Bad","computer":"bad host"},"#
        let unknownMode =
            #"{"id":"7F1C2A52-8B39-4B79-9A43-2B7D4D0B5E10","name":"X","computer":"pc02.example.com","#
            + #""display":{"mode":"hologram"}},"#
        text = text.replacingOccurrences(of: #""profiles" : ["#, with: #""profiles" : ["# + bad + unknownMode)
        try write(text)

        let loaded = store.load()
        #expect(loaded.profiles == [good])
        #expect(loaded.selectedID == good.id)
        guard case .partlyUnreadable(skipped: 2, let backup) = loaded.problem else {
            Issue.record("expected 2 skipped, got \(String(describing: loaded.problem))")
            return
        }
        #expect(try String(contentsOf: backup, encoding: .utf8) == text)

        // Saved without the damaged ones: the next start neither warns nor backs up again.
        let again = store.load()
        #expect(again.problem == nil)
        #expect(again.profiles == [good])
        #expect(try backups().count == 1)
    }

    /// The selected profile was the damaged one: the first readable one is selected instead.
    @Test func selectionOfASkippedProfileFallsBack() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(
            """
            {"version":1,"selectedID":"7F1C2A52-8B39-4B79-9A43-2B7D4D0B5E10","profiles":[
             {"id":"6F1C2A52-8B39-4B79-9A43-2B7D4D0B5E10","name":"Good","computer":"pc01.example.com"},
             {"id":"7F1C2A52-8B39-4B79-9A43-2B7D4D0B5E10","name":"Bad","computer":"bad host"}]}
            """)
        let loaded = store.load()
        #expect(loaded.selectedID == UUID(uuidString: "6F1C2A52-8B39-4B79-9A43-2B7D4D0B5E10"))
    }

    /// A file that cannot be read (permissions, a disk error) may be intact: it is not moved, and
    /// the app must not save over it.
    @Test func fileThatCannotBeReadIsLeftAlone() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
        let loaded = store.load()
        #expect(loaded.problem == .notSaved)
        #expect(!loaded.canSave)
        #expect(try backups().isEmpty)
    }

    /// Without a backup nothing may be saved over the damaged file.
    @Test(arguments: ["not json", #"{"profiles":[{"name":"Bad","computer":"bad host"}]}"#])
    func noBackupMeansNoSaving(_ text: String) throws {
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: store.fileURL.deletingLastPathComponent().path)
            try? FileManager.default.removeItem(at: directory)
        }
        try write(text)
        let folder = store.fileURL.deletingLastPathComponent()
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path)
        let loaded = store.load()
        #expect(loaded.problem == .notSaved)
        #expect(!loaded.canSave)
        #expect(try String(contentsOf: store.fileURL, encoding: .utf8) == text)
    }

    /// A newer CardGate may have added settings this one does not know: its file is only read.
    @Test func newerVersionIsNeverOverwritten() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = """
            {"version": 2, "profiles": [{"id":"6F1C2A52-8B39-4B79-9A43-2B7D4D0B5E10","name":"Office",
             "computer":"pc01.corp.example","gateway":"rdg.example.com"}], "future": true}
            """
        try write(text)
        let loaded = store.load()
        #expect(loaded.problem == .newerVersion)
        #expect(!loaded.canSave)
        #expect(loaded.profiles.map(\.name) == ["Office"])
        #expect(throws: ProfileStore.StoreError.newerVersion) {
            try store.save(profiles: [], selectedID: nil)
        }
        #expect(try String(contentsOf: store.fileURL, encoding: .utf8) == text)
    }
}

extension ProfileStoreTests {
    /// A newer version may store its file differently; it is never moved or written over.
    @Test(arguments: [
        #"{"version":2,"profiles":{"office":{"computer":"pc01.example.com"}}}"#,
        #"{"version":"2","profiles":[]}"#,
        #"{"version":1.5,"profiles":[]}"#,
    ])
    func newerOrUnknownVersionIsOnlyRead(_ text: String) throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try write(text)
        let loaded = store.load()
        #expect(loaded.problem == .newerVersion)
        #expect(!loaded.canSave)
        #expect(try backups().isEmpty)
        #expect(throws: ProfileStore.StoreError.newerVersion) { try store.save(profiles: [], selectedID: nil) }
        #expect(try String(contentsOf: store.fileURL, encoding: .utf8) == text)
    }
}

struct AppAlertTests {
    @Test func loadProblems() {
        let backup = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/x.json")
        #expect(AppAlert(.unreadable(backup: backup)) == .profilesUnreadable(backup: "~/Library/x.json"))
        #expect(
            AppAlert(.partlyUnreadable(skipped: 2, backup: backup))
                == .profilesPartlyUnreadable(skipped: 2, backup: "~/Library/x.json"))
        #expect(AppAlert(.newerVersion) == .profilesFromNewerVersion)
        #expect(AppAlert(.notSaved) == .profilesNotReadable)
    }

    @Test func clientCommandErrors() {
        #expect(AppAlert(FreeRDPCommand.BuildError.gatewayRequired) == .gatewayMissing)
        #expect(AppAlert(FreeRDPCommand.BuildError.invalidModulePath) == .modulePathUnusable)
    }

    /// Only problems that would lose data block saving.
    @Test func whatBlocksSaving() {
        let backup = URL(filePath: "/tmp/x.json")
        #expect(ProfileStore.Loaded(problem: .unreadable(backup: backup)).canSave)
        #expect(ProfileStore.Loaded(problem: .partlyUnreadable(skipped: 1, backup: backup)).canSave)
        #expect(!ProfileStore.Loaded(problem: .newerVersion).canSave)
        #expect(!ProfileStore.Loaded(problem: .notSaved).canSave)
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
        #expect(profile.display.scale == nil)
    }
}
