/// The display a profile opens full screen on: found by `key`, the name is shown and tells
/// identical displays apart.
public struct DisplayChoice: Codable, Equatable, Hashable, Sendable {
    /// `built-in`, or vendor, model and serial number (`ConnectedDisplay.key(vendor:model:serial:)`).
    public var key: String
    /// The name macOS showed when it was chosen.
    public var name: String

    public init(key: String, name: String) {
        self.key = key
        self.name = name
    }
}

/// A display connected to the Mac, as the settings offer it for full screen.
public struct ConnectedDisplay: Equatable, Hashable, Sendable {
    /// The name macOS shows (`NSScreen.localizedName`; in the app's language, identical models get a
    /// number by their order).
    public var name: String
    /// The CoreGraphics display ID (`NSScreenNumber`), valid while the display is connected.
    public var id: UInt32
    /// Stays the same across restarts, connections and languages (`DisplayChoice.key`).
    public var key: String

    public init(name: String, id: UInt32, key: String) {
        self.name = name
        self.id = id
        self.key = key
    }

    public static let builtInKey = "built-in"

    /// The key of an external display (CGDisplayVendorNumber, ModelNumber, SerialNumber; the serial
    /// number is 0 where the display does not tell it).
    public static func key(vendor: UInt32, model: UInt32, serial: UInt32) -> String {
        "\(vendor)-\(model)-\(serial)"
    }

    public var choice: DisplayChoice { DisplayChoice(key: key, name: name) }

    /// The connected display a profile chose, or `nil` (the main display) when it is not connected.
    /// The built-in display and one with a serial number are found by their key (their name changes
    /// with the language or the number macOS gives identical models); an external display without a
    /// serial number by its key and name (otherwise it may be its identical twin).
    public static func display(for choice: DisplayChoice?, among displays: [ConnectedDisplay]) -> ConnectedDisplay? {
        guard let choice else { return nil }
        let same = displays.filter { $0.key == choice.key }
        let named = same.first { $0.name == choice.name }
        return Self.hasSerialNumber(choice.key) ? named ?? same.first : named
    }

    /// The key tells the display apart from identical models (built in, or with a serial number).
    static func hasSerialNumber(_ key: String) -> Bool {
        key == builtInKey || !key.hasSuffix("-0")
    }

    /// What the settings offer besides the main display: the connected displays (the one the profile
    /// chose keeps its choice, so the picker shows it), then the chosen one if it is not connected.
    public static func options(chosen: DisplayChoice?, among displays: [ConnectedDisplay]) -> [Option] {
        let current = display(for: chosen, among: displays)
        var options = displays.map { display in
            Option(choice: display == current ? chosen ?? display.choice : display.choice, name: display.name)
        }
        if let chosen, current == nil {
            options.append(Option(choice: chosen, name: chosen.name, isConnected: false))
        }
        return options
    }

    public struct Option: Equatable, Hashable, Sendable {
        public var choice: DisplayChoice
        /// The name to show: the current one of a connected display.
        public var name: String
        public var isConnected: Bool

        public init(choice: DisplayChoice, name: String, isConnected: Bool = true) {
            self.choice = choice
            self.name = name
            self.isConnected = isConnected
        }
    }
}
