public import Foundation

/// Everything needed to connect to one remote computer.
public struct ConnectionProfile: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    /// Name shown to the user.
    public var name: String
    /// Remote computer.
    public var computer: HostAddress
    /// RD Gateway; `nil` connects directly.
    public var gateway: HostAddress?
    /// Explicit PKCS#11 module of the smart card middleware; `nil` = detect automatically.
    public var pkcs11Module: String?
    public var display: DisplaySettings
    public var redirection: RedirectionSettings

    public init(
        id: UUID = UUID(),
        name: String,
        computer: HostAddress,
        gateway: HostAddress? = nil,
        pkcs11Module: String? = nil,
        display: DisplaySettings = .init(),
        redirection: RedirectionSettings = .init()
    ) {
        self.id = id
        self.name = name
        self.computer = computer
        self.gateway = gateway
        self.pkcs11Module = pkcs11Module
        self.display = display
        self.redirection = redirection
    }
}

public struct DisplaySettings: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable {
        /// Resizable window, remote resolution follows the window size.
        case window
        /// Full screen on the current display.
        case fullScreen
        /// Full screen across all displays.
        case allDisplays
    }

    public var mode: Mode
    /// Initial window size in points; `nil` lets the client choose (fits the screen).
    public var windowSize: WindowSize?

    public init(mode: Mode = .window, windowSize: WindowSize? = nil) {
        self.mode = mode
        self.windowSize = windowSize
    }
}

public struct WindowSize: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Range accepted by RDP servers.
    public var isValid: Bool { (200...8192).contains(width) && (200...8192).contains(height) }

    public var description: String { "\(width)×\(height)" }

    /// Common sizes offered in the settings.
    public static let presets: [WindowSize] = [
        .init(width: 1280, height: 800),
        .init(width: 1440, height: 900),
        .init(width: 1680, height: 1050),
        .init(width: 1920, height: 1080),
        .init(width: 1920, height: 1200),
        .init(width: 2560, height: 1440),
    ]
}

public struct RedirectionSettings: Codable, Equatable, Sendable {
    public var clipboard: Bool
    /// Play remote audio on this Mac.
    public var audio: Bool

    public init(clipboard: Bool = true, audio: Bool = true) {
        self.clipboard = clipboard
        self.audio = audio
    }
}
