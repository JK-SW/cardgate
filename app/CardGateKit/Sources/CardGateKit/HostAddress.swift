import Foundation

/// A network endpoint given as `host` or `host:port`.
///
/// Values end up inside FreeRDP command line options (some of them comma separated sub-options),
/// so only plain DNS names and IPv4 addresses are accepted: no spaces, commas, colons in the host
/// part or other characters that could change the meaning of an option.
public struct HostAddress: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let host: String
    public let port: UInt16?

    public enum ParseError: Error, Equatable, Sendable {
        case empty
        case invalidHost
        case invalidPort
    }

    public init(host: String, port: UInt16? = nil) throws(ParseError) {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { throw .empty }
        guard Self.isValidHost(host) else { throw .invalidHost }
        if let port, port == 0 { throw .invalidPort }
        self.host = host.lowercased()
        self.port = port
    }

    /// Parses `host` or `host:port`.
    public init(parsing text: String) throws(ParseError) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .empty }
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        switch parts.count {
        case 1:
            try self.init(host: text)
        case 2:
            guard let port = UInt16(parts[1]) else { throw .invalidPort }
            try self.init(host: String(parts[0]), port: port)
        default:
            throw .invalidHost
        }
    }

    public var description: String {
        port.map { "\(host):\($0)" } ?? host
    }

    static func isValidHost(_ host: String) -> Bool {
        guard host.utf8.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard (1...63).contains(label.utf8.count),
                label.first != "-", label.last != "-"
            else { return false }
            return label.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-")
            }
        }
    }
}

extension HostAddress: Codable {
    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        do {
            try self.init(parsing: text)
        } catch {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid host address \(text)"))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
