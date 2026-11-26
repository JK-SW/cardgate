import Foundation
import Testing

@testable import CardGateKit

/// The saved log: the diagnostic information and the archive.
struct DiagnosticReportTests {
    @Test func text() {
        let report = DiagnosticReport(sections: [
            .init("Mac", [("macOS", "Version 26.2"), ("Model", "Mac15,3")]),
            .init("Card", [("Module", "Example\nCorp")]),
        ])
        #expect(report.text == "[Mac]\nmacOS: Version 26.2\nModel: Mac15,3\n\n[Card]\nModule: Example Corp\n")
    }

    @Test func pathWithoutTheUserName() {
        #expect(DiagnosticReport.anonymizedPath("/Users/jane/lib/m.dylib", home: "/Users/jane") == "~/lib/m.dylib")
        #expect(DiagnosticReport.anonymizedPath("/Users/janet/m.dylib", home: "/Users/jane") == "/Users/janet/m.dylib")
        #expect(
            DiagnosticReport.anonymizedPath("/usr/local/lib/m.dylib", home: "/Users/jane/") == "/usr/local/lib/m.dylib")
    }

    @Test func time() throws {
        let date = Date(timeIntervalSince1970: 1_795_000_000)
        let prague = try #require(TimeZone(identifier: "Europe/Prague"))
        #expect(DiagnosticReport.time(date, timeZone: prague) == "2026-11-18 11:06:40 UTC (local time UTC+01:00)")
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        #expect(DiagnosticReport.time(date, timeZone: newYork).hasSuffix("(local time UTC-05:00)"))
    }

    @Test func archive() throws {
        let data = try LogArchive.make(
            folder: "CardGate-log-2026-11-26-1639",
            files: [("important.txt", Data("a\n".utf8)), ("connection.log", Data("b\n".utf8))])
        let work = FileManager.default.temporaryDirectory.appending(path: "CardGateTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appending(path: "a.zip")
        try data.write(to: zip)
        let unzip = Process()
        unzip.executableURL = URL(filePath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, work.path]
        try unzip.run()
        unzip.waitUntilExit()
        let folder = work.appending(path: "CardGate-log-2026-11-26-1639")
        #expect(try String(contentsOf: folder.appending(path: "important.txt"), encoding: .utf8) == "a\n")
        #expect(try String(contentsOf: folder.appending(path: "connection.log"), encoding: .utf8) == "b\n")
        #expect(LogArchive.name(at: Date(timeIntervalSince1970: 0)).hasSuffix(".zip"))
    }

    /// The module and the card travel from the check process with the state and the reader.
    @Test func moduleInfoRoundTrip() throws {
        let info = PKCS11ModuleInfo(
            module: "Example – PKCS#11, 2.20", token: "Example – Card 1, hardware 1.0, firmware 2.1")
        let result = PKCS11ProbeResult(state: .ready, reader: "Example Reader", info: info)
        #expect(PKCS11ProbeResult(encoded: result.encoded) == result)
        // An older check without them, and one without a card.
        #expect(try #require(PKCS11ProbeResult(encoded: "0 1\nExample Reader")).info == nil)
        let noCard = try #require(PKCS11ProbeResult(encoded: "0 0\n\nExample – PKCS#11, 2.20\n"))
        #expect(noCard.info == PKCS11ModuleInfo(module: "Example – PKCS#11, 2.20", token: ""))
        #expect(PKCS11ModuleInfo(module: "A\u{7}B ", token: "").module == "AB")
        #expect(PKCS11ModuleInfo.describe("", "Card", ["firmware 1.0"]) == "Card, firmware 1.0")
    }
}
