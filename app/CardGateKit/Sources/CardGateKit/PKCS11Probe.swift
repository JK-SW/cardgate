import CPKCS11

/// What the PKCS#11 module of the middleware sees – the same view the FreeRDP client gets.
///
/// CryptoTokenKit may still list a card the PKCS#11 module no longer sees (e.g. after the Mac
/// slept); the card then has to be removed and inserted again.
public enum PKCS11CardState: Equatable, Sendable {
    case ready(certificates: Int)
    case noToken
    case noCertificates
    case moduleNotLoadable
    case failed(code: Int)

    public init(error: Int, tokens: Int, certificates: Int) {
        switch (error, tokens, certificates) {
        case (-1, _, _): self = .moduleNotLoadable
        case (0, 0, _): self = .noToken
        case (0, _, 0): self = .noCertificates
        case (0, _, let count): self = .ready(certificates: count)
        default: self = .failed(code: error)
        }
    }

    /// Text form used between the probe process and the app: `error tokens certificates`.
    public var encoded: String {
        switch self {
        case .ready(let count): "0 1 \(count)"
        case .noToken: "0 0 0"
        case .noCertificates: "0 1 0"
        case .moduleNotLoadable: "-1 0 0"
        case .failed(let code): "\(code) 0 0"
        }
    }

    public init?(encoded: String) {
        let numbers = encoded.split(separator: " ").compactMap { Int($0) }
        guard numbers.count == 3 else { return nil }
        self.init(error: numbers[0], tokens: numbers[1], certificates: numbers[2])
    }
}

public enum PKCS11Probe {
    /// Loads the module, looks at the tokens (no login, no PIN) and unloads it. Takes seconds with
    /// some middleware, so call it off the main thread – preferably in a separate process.
    public static func probe(module: String) -> PKCS11CardState {
        let result = cg_card_probe(module)
        return PKCS11CardState(error: result.error, tokens: Int(result.tokens), certificates: Int(result.certificates))
    }
}
