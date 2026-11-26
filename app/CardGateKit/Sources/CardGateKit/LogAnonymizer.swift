public import Foundation

/// Replaces what names the user's environment in the saved log (`LogArchive`) with "***": the
/// computer (its full name, its own name and its domain – also as the Kerberos realm), the gateway
/// and its domain, the connection's name in the window title, the Windows account the client logs
/// after signing in, principals and addresses ("name@domain") and the home folder. The archive can
/// then be passed on without editing; the log on this Mac and Copy Log keep everything.
public struct LogAnonymizer: Sendable {
    public static let mask = "***"
    /// The client's window title: "<name> – CardGate" (`FreeRDPCommand`).
    static let titleSuffix = " – CardGate"

    /// Names of hosts and domains, longest first: a domain inside a full name goes with it.
    private(set) var terms: [String]
    /// Connection names: hidden only in the window title, they may be ordinary words ("Windows").
    private(set) var titles: [String]
    let home: String

    /// - Parameters:
    ///   - computer: the computer's address as entered (a name or an IP address).
    ///   - gateway: the gateway's address.
    ///   - name: the connection's name (the title of the remote desktop window).
    public init(computer: String, gateway: String?, name: String, home: String = NSHomeDirectory()) {
        var terms = Self.hostTerms(computer, ownName: true)
        if let gateway { terms += Self.hostTerms(gateway, ownName: false) }
        self.terms = Self.sorted(terms)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        titles = name.isEmpty ? [] : [name]
        self.home = home.hasSuffix("/") ? String(home.dropLast()) : home
    }

    /// Also hides the computer, the gateway and the window title of the client's command line (the
    /// log's first line, "CardGate: /v:… /title:… – CardGate /gateway:g:…,…"): the log names what
    /// it connected to, also when the connection was changed since.
    public func adding(commandLine: String) -> LogAnonymizer {
        let arguments = commandLine.prefix { $0 != "\n" }
        func value(_ option: String) -> Substring? {
            guard let range = arguments.range(of: " " + option) else { return nil }
            return arguments[range.upperBound...]
        }
        func untilNextOption(_ text: Substring) -> String {
            String(text[..<(text.range(of: " /")?.lowerBound ?? text.endIndex)])
        }
        var copy = self
        if let computer = value("/v:").map(untilNextOption) {
            copy.terms += Self.hostTerms(Self.withoutPort(computer), ownName: true)
        }
        if let gateway = value("/gateway:g:").map(untilNextOption)?.split(separator: ",").first {
            copy.terms += Self.hostTerms(Self.withoutPort(String(gateway)), ownName: false)
        }
        // Up to the suffix: the name itself may contain " /".
        if let title = value("/title:"), let end = title.range(of: Self.titleSuffix) {
            copy.titles.append(String(title[..<end.lowerBound]))
        }
        copy.terms = Self.sorted(copy.terms)
        return copy
    }

    static func sorted(_ terms: [String]) -> [String] {
        Array(Set(terms.map { $0.lowercased() })).sorted { $0.count > $1.count }
    }

    /// "pc01.example.com:3389" → "pc01.example.com"; "[2001:db8::1]:3389" → "2001:db8::1".
    static func withoutPort(_ address: String) -> String {
        if address.hasPrefix("["), let end = address.firstIndex(of: "]") {
            return String(address[address.index(after: address.startIndex)..<end])
        }
        let parts = address.split(separator: ":")
        return parts.count == 2 && parts[1].allSatisfy(\.isNumber) ? String(parts[0]) : address
    }

    /// "pc01.corp.example.com" → itself, "corp.example.com" and, for the computer, "pc01" (the realm
    /// is the domain in capitals; replacing ignores case). A domain of one label ("com") stays, and so
    /// does a computer's own name that is an ordinary word of the log ("server").
    static func hostTerms(_ host: String, ownName: Bool) -> [String] {
        let host = host.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty else { return [] }
        var terms = [host]
        let labels = host.split(separator: ".").map(String.init)
        // Not for an IP address: its parts are numbers that appear everywhere.
        guard labels.count > 1, labels.contains(where: { $0.contains(where: \.isLetter) }) else { return terms }
        if labels.count > 2 { terms.append(labels.dropFirst().joined(separator: ".")) }
        if ownName, labels[0].count >= 3, !commonWords.contains(labels[0].lowercased()) { terms.append(labels[0]) }
        return terms
    }

    /// Words of the client's log that also serve as computer names.
    static let commonWords: Set<String> = [
        "server", "client", "computer", "desktop", "remote", "gateway", "terminal", "windows", "host", "session",
        "local", "localhost", "default", "user", "admin", "test", "office", "rdp", "pc",
    ]

    public func anonymize(_ text: String) -> String {
        var text = text
        // Principals and addresses: "user@EXAMPLE.COM", "TERMSRV/pc01@EXAMPLE.COM".
        text = Self.replace(#"[A-Za-z0-9._%+/$-]+@[A-Za-z0-9.-]+"#, in: text, with: Self.mask)
        for title in titles {
            text = text.replacingOccurrences(of: title + Self.titleSuffix, with: Self.mask + Self.titleSuffix)
        }
        for term in terms {
            // Whole names only: not "pc01" inside "pc012" or "server" inside ERRINFO_SERVER_….
            let pattern = "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: term) + "(?![A-Za-z0-9_])"
            text = Self.replace(pattern, in: text, with: Self.mask, caseInsensitive: true)
        }
        // The Windows account: "Logon Info V2 [DOMAIN\user [2]]".
        text = Self.replace(
            #"(\[client_common_save_session_info\]: [^\[\n]*\[)[^\n]*"#, in: text, with: "$1" + Self.mask + "]")
        if !home.isEmpty, home != "/" {
            text = text.replacingOccurrences(of: home + "/", with: "~/")
        }
        return text
    }

    static func replace(_ pattern: String, in text: String, with template: String, caseInsensitive: Bool = false)
        -> String
    {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        else { return text }
        return regex.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
