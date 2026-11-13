public import Foundation

/// Persists connection profiles as JSON. Contains no secrets.
///
/// Reading never loses data: a profile that cannot be read is skipped (the others load) and the
/// file is backed up first, an invalid file is moved aside, and a file from a newer CardGate
/// version or one that cannot be read or backed up is never overwritten.
public struct ProfileStore: Sendable {
    public let fileURL: URL

    /// The format this version writes; files with a higher (or unknown) version are only read.
    ///
    /// **Rule:** every change an older version cannot read (a new enum value, a new required field,
    /// another structure, a value an older version rejects) must raise this number. Older versions
    /// then leave the file alone; a profile they cannot read under the same version counts as
    /// damaged and is dropped from the file after a backup (`load`). Optional new fields that older
    /// versions ignore need no new version.
    public static let currentVersion = 1

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/CardGate/profiles.json` (see `AppDirectories`)
    public static func standard() throws -> ProfileStore {
        ProfileStore(fileURL: try AppDirectories.data().appending(path: "profiles.json"))
    }

    public enum StoreError: Error, Equatable, Sendable {
        /// The file was written by a newer CardGate version; saving would lose its data.
        case newerVersion
    }

    /// What went wrong while loading; the app tells the user.
    public enum LoadProblem: Equatable, Sendable {
        /// Nothing could be read; the file was moved to `backup` and a new one starts.
        case unreadable(backup: URL)
        /// `skipped` profiles could not be read; the file as it was is in `backup`, the rest was
        /// saved again.
        case partlyUnreadable(skipped: Int, backup: URL)
        /// Written by a newer version (see `StoreError.newerVersion`).
        case newerVersion
        /// The file could not be read or backed up (permissions, a disk error): nothing is saved
        /// over it while the app runs.
        case notSaved
    }

    public struct Loaded: Equatable, Sendable {
        public var profiles: [ConnectionProfile] = []
        public var selectedID: UUID?
        public var problem: LoadProblem?

        /// Saving would lose data the app could not read: the app must not save.
        public var canSave: Bool {
            problem != .newerVersion && problem != .notSaved
        }

        public init(profiles: [ConnectionProfile] = [], selectedID: UUID? = nil, problem: LoadProblem? = nil) {
            self.profiles = profiles
            // A selection that was skipped would point at nothing.
            self.selectedID = profiles.contains { $0.id == selectedID } ? selectedID : profiles.first?.id
            self.problem = problem
        }
    }

    struct Contents: Encodable {
        var version = ProfileStore.currentVersion
        var profiles: [ConnectionProfile]
        var selectedID: UUID?
    }

    /// Reads the file profile by profile: a damaged profile does not take the others with it.
    struct LenientContents: Decodable {
        var profiles: [Lenient]
        var selectedID: UUID?

        struct Lenient: Decodable {
            let profile: ConnectionProfile?

            init(from decoder: any Decoder) throws {
                profile = try? ConnectionProfile(from: decoder)
            }
        }

        enum CodingKeys: CodingKey {
            case profiles, selectedID
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            profiles = try container.decode([Lenient].self, forKey: .profiles)
            selectedID = try? container.decodeIfPresent(UUID.self, forKey: .selectedID)
        }
    }

    /// Loaded profiles and the selected one. A missing file means no profiles yet. A file that
    /// is not valid is moved to a backup; damaged profiles are skipped after backing up the file,
    /// which is then saved without them (so the backup and the message happen once). A file that
    /// cannot be read or backed up is left alone and must not be saved over (`Loaded.canSave`).
    public func load(now: Date = Date()) -> Loaded {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return Loaded() }
        guard let data = try? Data(contentsOf: fileURL) else {
            return Loaded(problem: .notSaved)  // e.g. no permission: the data may be fine
        }
        // The version first: a newer file may be shaped differently and must never be moved.
        if Self.isNewer(data) {
            let contents = try? JSONDecoder().decode(LenientContents.self, from: data)
            return Loaded(
                profiles: contents?.profiles.compactMap(\.profile) ?? [], selectedID: contents?.selectedID,
                problem: .newerVersion)
        }
        guard let contents = try? JSONDecoder().decode(LenientContents.self, from: data) else {
            let backup = backupURL(now: now)
            guard (try? manager.moveItem(at: fileURL, to: backup)) != nil else { return Loaded(problem: .notSaved) }
            return Loaded(problem: .unreadable(backup: backup))
        }
        let profiles = contents.profiles.compactMap(\.profile)
        let skipped = contents.profiles.count - profiles.count
        guard skipped > 0 else { return Loaded(profiles: profiles, selectedID: contents.selectedID) }
        let backup = backupURL(now: now)
        guard (try? manager.copyItem(at: fileURL, to: backup)) != nil else {
            return Loaded(profiles: profiles, selectedID: contents.selectedID, problem: .notSaved)
        }
        let loaded = Loaded(
            profiles: profiles, selectedID: contents.selectedID,
            problem: .partlyUnreadable(skipped: skipped, backup: backup))
        // If this fails, the next save tries again; the backup holds everything.
        try? save(profiles: loaded.profiles, selectedID: loaded.selectedID)
        return loaded
    }

    public func save(profiles: [ConnectionProfile], selectedID: UUID?) throws {
        if let data = try? Data(contentsOf: fileURL), Self.isNewer(data) {
            throw StoreError.newerVersion
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Contents(profiles: profiles, selectedID: selectedID))
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    /// The file is a JSON object whose `version` is higher than `currentVersion` or not a number
    /// this version understands. Files without a version are from the first version.
    static func isNewer(_ data: Data) -> Bool {
        guard let version = try? JSONDecoder().decode(VersionOnly.self, from: data) else { return false }
        return version.isUnknown || (version.number ?? 1) > currentVersion
    }

    private struct VersionOnly: Decodable {
        var number: Int?
        var isUnknown = false

        enum CodingKeys: String, CodingKey {
            case version
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.version) else { return }
            if let number = try? container.decode(Int.self, forKey: .version) {
                self.number = number
            } else {
                isUnknown = true  // e.g. "2" or 2.1: written by something newer
            }
        }
    }

    /// `profiles.unreadable-<date>.json` next to the file.
    func backupURL(now: Date) -> URL {
        let stamp = now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
            .replacingOccurrences(of: ":", with: "")
        var url = fileURL.deletingLastPathComponent().appending(path: "profiles.unreadable-\(stamp).json")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            url = fileURL.deletingLastPathComponent().appending(path: "profiles.unreadable-\(stamp)-\(counter).json")
            counter += 1
        }
        return url
    }
}
