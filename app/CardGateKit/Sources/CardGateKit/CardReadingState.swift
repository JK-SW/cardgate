/// "Reading the card…": a reader reports an inserted card seconds before the card's software
/// offers its certificates. Shown from the insertion until certificates arrive, the card is
/// removed, or reading takes too long (the card has no sign-in certificates for us).
public struct CardReadingState: Equatable, Sendable {
    public static let givesUpAfter: Duration = .seconds(20)

    public private(set) var isReading = false

    public init() {}

    /// A reader reported a card (`present`) or none. Returns whether reading started, so the caller
    /// schedules `gaveUp()` after `givesUpAfter`.
    public mutating func cardInReader(_ present: Bool, hasCertificates: Bool) -> Bool {
        isReading = present && !hasCertificates
        return isReading
    }

    /// The certificates on the inserted cards changed.
    public mutating func certificatesChanged(found: Bool) {
        if found { isReading = false }
    }

    public mutating func gaveUp() {
        isReading = false
    }
}
