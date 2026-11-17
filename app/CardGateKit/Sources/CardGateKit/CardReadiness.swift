public import Foundation

/// How a status reads at a glance (the app gives each a color).
public enum StatusTone: Equatable, Sendable {
    case success, warning, error, info, neutral
}

/// What the system reports about the inserted cards.
public struct InsertedCards: Equatable, Sendable {
    /// All certificates on the inserted cards.
    public var certificates: [CardCertificate]
    /// A card was inserted and is being read.
    public var isReading: Bool
    /// The system lists the card but the middleware's PKCS#11 module does not see it.
    public var needsReinsert: Bool

    public init(certificates: [CardCertificate] = [], isReading: Bool = false, needsReinsert: Bool = false) {
        self.certificates = certificates
        self.isReading = isReading
        self.needsReinsert = needsReinsert
    }
}

/// Whether the smart card software is installed and a card with a sign-in certificate is inserted.
public enum CardReadiness: Equatable, Sendable {
    case moduleProblem(ModuleProblem)
    case noMiddleware
    case needsReinsert
    /// `expiresInDays`: the certificate expires within `CardCertificate.expiryWarningDays`.
    /// `renewedOnCard`: the connection is set to an older certificate although a renewed one,
    /// which does not expire soon, is on the card.
    case ready(CardCertificate, expiresInDays: Int?, renewedOnCard: Bool = false)
    case expired
    case reading
    case noCard
    case noSignInCertificate

    /// The state to tell, in the order the problems are worth telling: what keeps the card from
    /// being used at all first.
    /// - Parameter signInCertificate: the certificate the selected connection would sign in with.
    public static func evaluate(
        moduleProblem: ModuleProblem?, hasMiddleware: Bool, cards: InsertedCards,
        signInCertificate: CardCertificate?, at date: Date
    ) -> CardReadiness {
        if let moduleProblem { return .moduleProblem(moduleProblem) }
        if !hasMiddleware { return .noMiddleware }
        if cards.needsReinsert { return .needsReinsert }
        if let signInCertificate {
            // The one the connection signs in with (chosen in its settings, or the newest).
            let days = signInCertificate.expiryWarning(at: date)
            let newest = CardCertificate.signInCertificate(in: cards.certificates, at: date)
            let renewed =
                days != nil && newest != nil && newest != signInCertificate && newest?.expiryWarning(at: date) == nil
            return .ready(signInCertificate, expiresInDays: days, renewedOnCard: renewed)
        }
        if CardCertificate.allLogonCertificatesExpired(cards.certificates, at: date) { return .expired }
        if cards.isReading { return .reading }
        return cards.certificates.isEmpty ? .noCard : .noSignInCertificate
    }

    public var tone: StatusTone {
        switch self {
        case .moduleProblem(.invalidSignature), .moduleProblem(.unreadable): .error
        case .moduleProblem, .noMiddleware, .needsReinsert, .expired, .noSignInCertificate: .warning
        case .ready(_, let days, _): days == nil ? .success : .warning
        case .reading: .info
        case .noCard: .neutral
        }
    }
}
