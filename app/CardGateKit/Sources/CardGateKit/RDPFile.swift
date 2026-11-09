public import Foundation

/// Minimal reader of `.rdp` files saved by the Microsoft Remote Desktop client.
///
/// The format is one `name:type:value` setting per line; mstsc writes UTF-16LE with a BOM,
/// other tools UTF-8.
public struct RDPFile: Equatable, Sendable {
    /// Settings by lower-cased name.
    public private(set) var settings: [String: String] = [:]

    public enum ReadError: Error, Equatable, Sendable {
        case unreadableEncoding
        case missingComputer
        case invalidAddress(String)
    }

    public init(data: Data) throws(ReadError) {
        guard let text = Self.decode(data) else { throw .unreadableEncoding }
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let parts = rawLine.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3 else { continue }
            let name = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty else { continue }
            settings[name] = parts[2].trimmingCharacters(in: .whitespaces)
        }
    }

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    public subscript(name: String) -> String? {
        settings[name.lowercased()].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Creates a profile from the file. Values that are not set keep the profile defaults.
    public func makeProfile(name: String) throws(ReadError) -> ConnectionProfile {
        guard let full = self["full address"] else { throw .missingComputer }
        let computer: HostAddress
        do { computer = try HostAddress(parsing: full) } catch { throw .invalidAddress(full) }

        var gateway: HostAddress?
        // gatewayusagemethod 0 = never use the gateway.
        if let host = self["gatewayhostname"], self["gatewayusagemethod"] != "0" {
            do { gateway = try HostAddress(parsing: host) } catch { throw .invalidAddress(host) }
        }

        var display = DisplaySettings()
        if self["screen mode id"] == "2" {
            display.mode = self["use multimon"] == "1" ? .allDisplays : .fullScreen
        }
        if let width = self["desktopwidth"].flatMap(Int.init),
            let height = self["desktopheight"].flatMap(Int.init)
        {
            let size = WindowSize(width: width, height: height)
            if size.isValid { display.windowSize = size }
        }

        var redirection = RedirectionSettings()
        if let clipboard = self["redirectclipboard"] { redirection.clipboard = clipboard != "0" }
        // audiomode 0 = play on this computer.
        if let audio = self["audiomode"] { redirection.audio = audio == "0" }

        return ConnectionProfile(
            name: name, computer: computer, gateway: gateway, display: display, redirection: redirection)
    }

    static func decode(_ data: Data) -> String? {
        if data.starts(with: [0xFF, 0xFE]) {
            return String(data: data.dropFirst(2), encoding: .utf16LittleEndian)
        }
        if data.starts(with: [0xFE, 0xFF]) {
            return String(data: data.dropFirst(2), encoding: .utf16BigEndian)
        }
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(data: data.dropFirst(3), encoding: .utf8)
        }
        return String(data: data, encoding: .utf8)
    }
}
