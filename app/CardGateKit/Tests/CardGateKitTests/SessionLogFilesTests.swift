import CardGateKit
import Foundation
import Testing

struct SessionLogFilesTests {
    @Test func keepsTheLastFewLogs() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cardgate-logs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let logs = SessionLogFiles(directory: directory, keep: 3)

        for run in 1...4 {
            let handle = try logs.startNew()
            handle.write(Data("run \(run)".utf8))
            try handle.close()
        }

        func content(_ index: Int) throws -> String {
            try String(contentsOf: logs.url(index: index), encoding: .utf8)
        }
        #expect(try content(0) == "run 4")
        #expect(try content(1) == "run 3")
        #expect(try content(2) == "run 2")
        #expect(!FileManager.default.fileExists(atPath: logs.url(index: 3).path(percentEncoded: false)))
        #expect(logs.latest.lastPathComponent == "last-session.log")
    }

    @Test func nameOfASavedLog() throws {
        let date = try #require(
            Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 16, minute: 5)))
        #expect(SessionLogFiles.exportName(at: date) == "CardGate-log-2026-11-26-1605.log")
    }
}
