import CPKCS11

/// What the PKCS#11 module of the middleware sees – the same view the FreeRDP client gets.
///
/// CryptoTokenKit may still list a card the PKCS#11 module no longer sees (e.g. after the Mac
/// slept); the card then has to be removed and inserted again.
public enum PKCS11CardState: Equatable, Sendable {
    /// A token is present (certificates are listed through CryptoTokenKit).
    case ready
    case noToken
    case moduleNotLoadable
    case failed(code: Int)

    public init(error: Int, tokens: Int) {
        switch (error, tokens) {
        case (-1, _): self = .moduleNotLoadable
        case (0, 0): self = .noToken
        case (0, _): self = .ready
        default: self = .failed(code: error)
        }
    }

    /// Text form used between the probe process and the app: `error tokens`.
    public var encoded: String {
        switch self {
        case .ready: "0 1"
        case .noToken: "0 0"
        case .moduleNotLoadable: "-1 0"
        case .failed(let code): "\(code) 0"
        }
    }

    public init?(encoded: String) {
        let numbers = encoded.split(separator: " ").compactMap { Int($0) }
        guard numbers.count == 2 else { return nil }
        self.init(error: numbers[0], tokens: numbers[1])
    }
}

/// What the card says about its user PIN (read without logging in).
public struct PINPolicy: Equatable, Sendable {
    public var minLength: Int
    public var maxLength: Int
    /// A wrong PIN was entered since the last correct one.
    public var countLow: Bool
    /// The next wrong PIN locks the card.
    public var finalTry: Bool
    public var locked: Bool

    /// Used when the card does not report usable limits.
    public static let fallbackLengths = 4...16

    public init(minLength: Int, maxLength: Int, countLow: Bool = false, finalTry: Bool = false, locked: Bool = false) {
        self.minLength = minLength
        self.maxLength = maxLength
        self.countLow = countLow
        self.finalTry = finalTry
        self.locked = locked
    }

    /// From PKCS#11 `CK_TOKEN_INFO` values; implausible limits are replaced by the fallback.
    public init(minLength: UInt, maxLength: UInt, flags: UInt) {
        var lengths = Self.fallbackLengths
        if minLength > 0, maxLength >= minLength, maxLength <= 255 {
            lengths = Int(minLength)...Int(maxLength)
        }
        self.init(
            minLength: lengths.lowerBound, maxLength: lengths.upperBound,
            countLow: flags & 0x1_0000 != 0,  // CKF_USER_PIN_COUNT_LOW
            finalTry: flags & 0x2_0000 != 0,  // CKF_USER_PIN_FINAL_TRY
            locked: flags & 0x4_0000 != 0)  // CKF_USER_PIN_LOCKED
    }

    public static let unknown = PINPolicy(
        minLength: fallbackLengths.lowerBound, maxLength: fallbackLengths.upperBound)

    /// A PIN that can be offered to the card: right length, not locked. Never send anything else –
    /// every rejected PIN counts towards locking the card.
    public func accepts(_ pin: String) -> Bool {
        !locked && (minLength...maxLength).contains(pin.count)
    }
}

public enum PKCS11Probe {
    /// Loads the module, looks at the tokens (no login, no PIN) and unloads it. Takes seconds with
    /// some middleware, so call it off the main thread – preferably in a separate process.
    public static func probe(module: String) -> PKCS11CardState {
        let result = cg_card_probe(module)
        return PKCS11CardState(error: result.error, tokens: Int(result.tokens))
    }

    /// PIN policy of the inserted card, or `nil` if no card is available.
    public static func pinPolicy(module: String) -> PINPolicy? {
        let result = cg_card_probe(module)
        guard result.error == 0, result.tokens > 0 else { return nil }
        return PINPolicy(
            minLength: UInt(result.pin_min_length), maxLength: UInt(result.pin_max_length),
            flags: UInt(result.token_flags))
    }
}
