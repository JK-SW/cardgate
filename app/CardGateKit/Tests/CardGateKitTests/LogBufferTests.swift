import CardGateKit
import Testing

struct LogBufferTests {
    @Test func keepsTheNewestLinesWithUniqueNumbers() {
        var buffer = LogBuffer(capacity: 100)
        for number in 0..<1000 { buffer.append("line \(number)") }
        #expect(buffer.lines.count >= 100)
        #expect(buffer.lines.count < 110)
        #expect(buffer.lines.last == .init(id: 999, text: "line 999"))
        #expect(Set(buffer.lines.map(\.id)).count == buffer.lines.count)
        // Numbers keep growing after old lines were dropped and after clearing.
        buffer.removeAll()
        buffer.append("next")
        #expect(buffer.lines == [.init(id: 1000, text: "next")])
        #expect(buffer.texts == ["next"])
    }
}
