public import Foundation

/// Web addresses of the project.
public enum ProjectLinks {
    public static let sourceCode = link("https://github.com/JK-SW/cardgate")
    public static let donation = link("https://ko-fi.com/jirikubinek")

    /// The user guide on GitHub in the language the app is shown in (English otherwise).
    public static func userGuide(language: String?) -> URL {
        switch language?.prefix(2) {
        case "cs": link("https://github.com/JK-SW/cardgate/blob/main/docs/navod.cs.md")
        case "sk": link("https://github.com/JK-SW/cardgate/blob/main/docs/navod.sk.md")
        default: link("https://github.com/JK-SW/cardgate/blob/main/docs/user-guide.en.md")
        }
    }

    private static func link(_ address: StaticString) -> URL {
        guard let url = URL(string: "\(address)") else { preconditionFailure("invalid URL \(address)") }
        return url
    }
}

/// A one-time, unobtrusive offer to support the author.
///
/// Shown only after the app has proven useful (enough successful connections over some days) and
/// never again once closed or used. The counters stay in the local preferences; nothing is sent
/// anywhere. Administrators can turn the offer off with the `DonationPromptDisabled` preference
/// (e.g. `defaults write io.github.jk-sw.cardgate DonationPromptDisabled -bool true` or a
/// configuration profile).
public struct DonationPrompt {
    public static let requiredConnections = 20
    public static let minimumDays = 7

    static let connectionsKey = "DonationPrompt.SuccessfulConnections"
    static let firstUseKey = "DonationPrompt.FirstUse"
    static let finishedKey = "DonationPrompt.Finished"
    public static let disabledKey = "DonationPromptDisabled"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Call when a connection reached the remote desktop.
    public func recordSuccessfulConnection(at date: Date = Date()) {
        guard !isFinished else { return }
        if defaults.object(forKey: Self.firstUseKey) == nil {
            defaults.set(date, forKey: Self.firstUseKey)
        }
        defaults.set(successfulConnections + 1, forKey: Self.connectionsKey)
    }

    /// Whether to offer support now (call only at a calm moment, e.g. after a disconnect).
    public func isDue(at date: Date = Date()) -> Bool {
        guard !isFinished, !defaults.bool(forKey: Self.disabledKey),
            successfulConnections >= Self.requiredConnections,
            let firstUse = defaults.object(forKey: Self.firstUseKey) as? Date
        else { return false }
        return date.timeIntervalSince(firstUse) >= Double(Self.minimumDays) * 86_400
    }

    /// The offer was closed or used: never show it again.
    public func finish() {
        defaults.set(true, forKey: Self.finishedKey)
    }

    var successfulConnections: Int { defaults.integer(forKey: Self.connectionsKey) }
    var isFinished: Bool { defaults.bool(forKey: Self.finishedKey) }
}
