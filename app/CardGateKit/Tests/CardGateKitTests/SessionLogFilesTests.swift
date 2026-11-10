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
}
