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
    /// SHA-1 fingerprint of the certificate to sign in with; `nil` = newest valid one on the card.
    public var certificateSHA1: String?
    public var display: DisplaySettings
    public var redirection: RedirectionSettings
    public var input: InputSettings

    public init(
        id: UUID = UUID(),
        name: String,
        computer: HostAddress,
        gateway: HostAddress? = nil,
        pkcs11Module: String? = nil,
        certificateSHA1: String? = nil,
        display: DisplaySettings = .init(),
        redirection: RedirectionSettings = .init(),
        input: InputSettings = .init()
    ) {
        self.id = id
        self.name = name
        self.computer = computer
        self.gateway = gateway
        self.pkcs11Module = pkcs11Module
        self.certificateSHA1 = certificateSHA1
        self.display = display
        self.redirection = redirection
        self.input = input
    }

    // Settings added in later versions are optional so older saved profiles keep loading.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        computer = try container.decode(HostAddress.self, forKey: .computer)
        gateway = try container.decodeIfPresent(HostAddress.self, forKey: .gateway)
        pkcs11Module = try container.decodeIfPresent(String.self, forKey: .pkcs11Module)
        certificateSHA1 = try container.decodeIfPresent(String.self, forKey: .certificateSHA1)
        display = try container.decodeIfPresent(DisplaySettings.self, forKey: .display) ?? .init()
        redirection = try container.decodeIfPresent(RedirectionSettings.self, forKey: .redirection) ?? .init()
        input = try container.decodeIfPresent(InputSettings.self, forKey: .input) ?? .init()
    }
}

public struct InputSettings: Codable, Equatable, Sendable {
    /// Scroll in the remote session in the same direction as on this Mac ("natural scrolling"
    /// setting of macOS). When off, the direction is converted to the classic Windows one.
    public var scrollLikeThisMac: Bool

    public init(scrollLikeThisMac: Bool = true) {
        self.scrollLikeThisMac = scrollLikeThisMac
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
    /// Size of text and apps on the remote desktop in percent; `nil` follows the display
    /// (200 % on a Retina display, otherwise 100 %).
    public var scale: Int?

    public init(mode: Mode = .fullScreen, windowSize: WindowSize? = nil, scale: Int? = nil) {
        self.mode = mode
        self.windowSize = windowSize
        self.scale = scale
    }

    /// The chosen scale if RDP accepts it; `nil` (follow the display) otherwise.
    public var validScale: Int? {
        scale.flatMap { Self.scaleRange.contains($0) ? $0 : nil }
    }

    /// Range of the desktop scale factor in RDP ([MS-RDPBCGR] 2.2.1.3.2).
    public static let scaleRange = 100...500
    /// Scales offered in the settings: the steps Windows itself offers.
    public static let scalePresets = [100, 125, 150, 175, 200, 225, 250, 300]
}

public struct WindowSize: Codable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public var width: Int
    public var height: Int

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Range accepted by RDP servers (in pixels).
    public var isValid: Bool { (200...8192).contains(width) && (200...8192).contains(height) }

    public var description: String { "\(width)×\(height)" }

    /// Common window sizes offered in the settings, in points (what the user sees on screen).
    public static let presets: [WindowSize] = [
        .init(width: 1024, height: 640),
        .init(width: 1280, height: 800),
        .init(width: 1440, height: 900),
        .init(width: 1680, height: 1050),
        .init(width: 1920, height: 1080),
        .init(width: 2048, height: 1152),
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
