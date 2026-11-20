public import Foundation

/// What `ConnectionSecurity.automatic` remembered per connection (user defaults, not the profiles
/// file: it is no setting, and the profile editor must not overwrite it with an older copy).
/// Keyed by profile and computer: another computer in the same profile starts over.
public struct SecurityMemory {
    /// User defaults key: profile ID and computer → `RememberedSecurity` (JSON).
    public static let defaultsKey = "RememberedSecurity"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The user's memory, or with test data (`AppDirectories.dataDirectoryVariable`, Debug builds)
    /// a separate one, empty at each launch: test connections never change the user's.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> SecurityMemory
    {
        guard AppDirectories.usesTestData(environment: environment),
            let defaults = UserDefaults(suiteName: testSuite)
        else { return SecurityMemory() }
        defaults.removePersistentDomain(forName: testSuite)
        return SecurityMemory(defaults: defaults)
    }

    static let testSuite = "io.github.jk-sw.cardgate.test-data"

    static func key(for profile: ConnectionProfile) -> String {
        "\(profile.id.uuidString)|\(profile.computer.description.lowercased())"
    }

    /// Whether NLA works depends on the gateway too (its KDC proxy).
    static func nlaFailedKey(for profile: ConnectionProfile) -> String {
        key(for: profile) + "|nla-failed|" + (profile.gateway?.description.lowercased() ?? "")
    }

    private var entries: [String: Any] {
        get { defaults.dictionary(forKey: Self.defaultsKey) ?? [:] }
        nonmutating set { defaults.set(newValue, forKey: Self.defaultsKey) }
    }

    public func remembered(for profile: ConnectionProfile) -> RememberedSecurity? {
        guard let data = entries[Self.key(for: profile)] as? Data else { return nil }
        return try? JSONDecoder().decode(RememberedSecurity.self, from: data)
    }

    public func remember(_ value: RememberedSecurity, for profile: ConnectionProfile) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        entries[Self.key(for: profile)] = data
    }

    /// The remembered method stays the weakest allowed, and the next attempt lets the computer
    /// choose among the others (`SecurityPlan.Outcome.letComputerChooseAgain`).
    public func letComputerChooseAgain(for profile: ConnectionProfile) {
        guard var value = remembered(for: profile) else { return }
        value.date = .distantPast
        remember(value, for: profile)
    }

    /// Forgets everything for the connection: the next attempt lets the computer choose among all
    /// methods (the user accepted weaker security, or the connection was deleted).
    public func forget(for profile: ConnectionProfile) {
        let key = Self.key(for: profile)
        entries = entries.filter { $0.key != key && !$0.key.hasPrefix(key + "|") }
    }

    /// Automatic security let the computer choose, it chose NLA and Kerberos with the card failed
    /// (e.g. the gateway has no KDC proxy): for `nlaFailedValidity` the computer chooses
    /// without NLA, as connections did before. Never after NLA was remembered (no unnoticed
    /// weakening of a computer known to accept it).
    public func rememberNLAFailed(for profile: ConnectionProfile, at date: Date) {
        entries[Self.nlaFailedKey(for: profile)] = date
    }

    /// The user wants to try NLA again (the computer requires it).
    public func forgetNLAFailed(for profile: ConnectionProfile) {
        entries[Self.nlaFailedKey(for: profile)] = nil
    }

    public func nlaRecentlyFailed(for profile: ConnectionProfile, at now: Date) -> Bool {
        guard let date = entries[Self.nlaFailedKey(for: profile)] as? Date else { return false }
        return date <= now && now.timeIntervalSince(date) < Self.nlaFailedValidity
    }

    /// Shorter than `RememberedSecurity.validity`: the failure may have been passing (one attempt a
    /// week where it lasts, e.g. no KDC proxy).
    public static let nlaFailedValidity: TimeInterval = 7 * 24 * 60 * 60

    /// Root CAs of card certificates found before (SHA-1 → DER; `PKINITAnchor`): found once, e.g.
    /// on the organization's network, they serve where the download is not reachable.
    public static let anchorsKey = "PKINITAnchors"

    public func anchor(forCertificate sha1: String) -> Data? {
        defaults.dictionary(forKey: Self.anchorsKey)?[sha1.lowercased()] as? Data
    }

    /// Keeps at most `maximumAnchors`: when full, the others go (cards of the past).
    public func rememberAnchor(_ root: Data, forCertificate sha1: String) {
        var anchors = defaults.dictionary(forKey: Self.anchorsKey) ?? [:]
        if anchors.count >= Self.maximumAnchors { anchors = [:] }
        anchors[sha1.lowercased()] = root
        defaults.set(anchors, forKey: Self.anchorsKey)
    }

    static let maximumAnchors = 10

    /// Forgets all root CAs (no connection left).
    public func forgetAnchors() {
        defaults.removeObject(forKey: Self.anchorsKey)
    }

    /// Drops what was remembered for profiles that no longer exist or another computer they had.
    public func keepOnly(_ profiles: [ConnectionProfile]) {
        let current = entries
        let keys = Set(profiles.map(Self.key(for:)))
        let kept = current.filter { entry in
            keys.contains(entry.key) || keys.contains { entry.key.hasPrefix($0 + "|") }
        }
        if kept.count != current.count { entries = kept }
    }
}
