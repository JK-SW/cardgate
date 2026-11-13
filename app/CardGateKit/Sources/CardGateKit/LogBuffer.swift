/// The most recent lines of a connection log, each with a number that never repeats, so a list
/// keeps its rows (and the scroll position at the end) when old lines are dropped.
public struct LogBuffer: Equatable, Sendable {
    public struct Line: Identifiable, Equatable, Sendable {
        public let id: Int
        public let text: String

        public init(id: Int, text: String) {
            self.id = id
            self.text = text
        }
    }

    public private(set) var lines: [Line] = []
    public let capacity: Int
    private var nextID = 0
    /// Old lines are dropped in batches, not one by one with every new line.
    private var slack: Int { max(1, capacity / 10) }

    public init(capacity: Int) {
        self.capacity = max(1, capacity)
    }

    public mutating func append(_ text: String) {
        lines.append(Line(id: nextID, text: text))
        nextID += 1
        if lines.count >= capacity + slack { lines.removeFirst(lines.count - capacity) }
    }

    public mutating func removeAll() {
        lines.removeAll()
    }

    public var texts: [String] { lines.map(\.text) }
}
