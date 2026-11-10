public import Foundation

/// Persists connection profiles as JSON. Contains no secrets.
public struct ProfileStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/CardGate/profiles.json` (see `AppDirectories`)
    public static func standard() throws -> ProfileStore {
        ProfileStore(fileURL: try AppDirectories.data().appending(path: "profiles.json"))
    }

    struct Contents: Codable, Equatable {
        var version = 1
        var profiles: [ConnectionProfile]
        var selectedID: UUID?
    }

    /// Loaded profiles and the selected one. A missing file means no profiles yet.
    public func load() throws -> (profiles: [ConnectionProfile], selectedID: UUID?) {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            return ([], nil)
        }
        let contents = try JSONDecoder().decode(Contents.self, from: Data(contentsOf: fileURL))
        return (contents.profiles, contents.selectedID)
    }

    public func save(profiles: [ConnectionProfile], selectedID: UUID?) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Contents(profiles: profiles, selectedID: selectedID))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
