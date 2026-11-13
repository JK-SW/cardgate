import Foundation

/// A network endpoint given as `host`, `host:port`, `[ipv6]` or `[ipv6]:port`.
///
/// Values end up inside FreeRDP command line options (some of them comma separated sub-options),
/// so only plain ASCII DNS names, IPv4 and bracketed IPv6 addresses are accepted: no spaces, commas
/// or other characters that could change the meaning of an option. Internationalized domain names
/// have to be entered in their ASCII (punycode, `xn--…`) form. Underscores (common in Windows
/// computer names) are accepted, and the dot of a fully qualified name (`pc01.example.com.`) is
/// dropped.
public struct HostAddress: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let host: String
    public let port: UInt16?
    /// `host` is an IPv6 address (written in brackets).
    public let isIPv6: Bool

    public enum ParseError: Error, Equatable, Sendable {
        case empty
        case invalidHost
        case invalidPort
    }

    public init(host: String, port: UInt16? = nil) throws(ParseError) {
        var host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { throw .empty }
        if host.count > 1, host.hasSuffix("."), !host.hasSuffix("..") { host.removeLast() }
        if let port, port == 0 { throw .invalidPort }
        if Self.isValidHost(host) {
            isIPv6 = false
        } else if Self.isIPv6(host) {
            isIPv6 = true
        } else {
            throw .invalidHost
        }
        self.host = host.lowercased()
        self.port = port
    }

    /// Parses `host` or `host:port`.
    public init(parsing text: String) throws(ParseError) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .empty }
        if text.hasPrefix("[") {
            guard let close = text.firstIndex(of: "]") else { throw .invalidHost }
            let address = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            guard Self.isIPv6(address) else { throw .invalidHost }
            if rest.isEmpty {
                try self.init(host: address)
            } else {
                guard rest.hasPrefix(":"), let port = UInt16(rest.dropFirst()) else { throw .invalidPort }
                try self.init(host: address, port: port)
            }
            return
        }
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
        let host = isIPv6 ? "[\(self.host)]" : self.host
        return port.map { "\(host):\($0)" } ?? host
    }

    static func isIPv6(_ text: String) -> Bool {
        var address = in6_addr()
        return text.utf8.allSatisfy { $0 < 0x80 } && inet_pton(AF_INET6, text, &address) == 1
    }

    static func isValidHost(_ host: String) -> Bool {
        guard host.utf8.count <= 253 else { return false }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard (1...63).contains(label.utf8.count),
                label.first != "-", label.last != "-"
            else { return false }
            return label.unicodeScalars.allSatisfy { scalar in
                scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "-" || scalar == "_")
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
