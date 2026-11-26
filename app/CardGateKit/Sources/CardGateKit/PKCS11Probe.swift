import CPKCS11
import CryptoKit
import Foundation

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
    /// The limits come from the card (not the fallback), so they can be shown to the user.
    public var lengthsKnown: Bool

    /// Used when the card does not report usable limits.
    public static let fallbackLengths = 4...16

    public init(
        minLength: Int, maxLength: Int, countLow: Bool = false, finalTry: Bool = false, locked: Bool = false,
        lengthsKnown: Bool = true
    ) {
        self.lengthsKnown = lengthsKnown
        self.minLength = minLength
        self.maxLength = maxLength
        self.countLow = countLow
        self.finalTry = finalTry
        self.locked = locked
    }

    /// From PKCS#11 `CK_TOKEN_INFO` values; implausible limits are replaced by the fallback.
    public init(minLength: UInt, maxLength: UInt, flags: UInt) {
        var lengths = Self.fallbackLengths
        let plausible = minLength > 0 && maxLength >= minLength && maxLength <= 255
        if plausible {
            lengths = Int(minLength)...Int(maxLength)
        }
        self.init(
            minLength: lengths.lowerBound, maxLength: lengths.upperBound,
            countLow: flags & 0x1_0000 != 0,  // CKF_USER_PIN_COUNT_LOW
            finalTry: flags & 0x2_0000 != 0,  // CKF_USER_PIN_FINAL_TRY
            locked: flags & 0x4_0000 != 0,  // CKF_USER_PIN_LOCKED
            lengthsKnown: plausible)
    }

    public static let unknown = PINPolicy(
        minLength: fallbackLengths.lowerBound, maxLength: fallbackLengths.upperBound, lengthsKnown: false)

    /// A PIN that can be offered to the card: right length, not locked. Never send anything else –
    /// every rejected PIN counts towards locking the card.
    public func accepts(_ pin: String) -> Bool {
        !locked && (minLength...maxLength).contains(pin.count)
    }
}

/// What the PKCS#11 module says about itself and the card, for the diagnostic information (no
/// label or serial number of the card: they may name its holder).
public struct PKCS11ModuleInfo: Equatable, Sendable {
    /// "Example Corp – Example PKCS#11 library, 2.20"
    public var module: String
    /// "Example Corp – Example Card, hardware 1.0, firmware 2.1"; empty without a card.
    public var token: String

    public init(module: String, token: String) {
        self.module = Self.clean(module)
        self.token = Self.clean(token)
    }

    /// One line, without control characters (the text travels between processes line by line).
    static func clean(_ text: String) -> String {
        String(text.unicodeScalars.filter { $0.value >= 0x20 && $0.value != 0x7F }.map(Character.init))
            .trimmingCharacters(in: .whitespaces)
    }

    /// "maker – name version" from the module's or token's fields, leaving out what is empty.
    static func describe(_ maker: String, _ name: String, _ details: [String]) -> String {
        let title = [maker, name].filter { !$0.isEmpty }.joined(separator: " – ")
        return ([title] + details).filter { !$0.isEmpty }.joined(separator: ", ")
    }
}

/// Card state and the reader holding the card, as found by `PKCS11Probe`.
public struct PKCS11ProbeResult: Equatable, Sendable {
    public var state: PKCS11CardState
    /// The module and the card, when the module could be asked (`nil` from an older check).
    public var info: PKCS11ModuleInfo?
    /// Name of the smart card reader with the token, when exactly one token is present. Only this
    /// reader is redirected to the remote computer, so an empty reader (e.g. in a keyboard) does
    /// not confuse the Windows sign-in.
    public var reader: String?

    public init(state: PKCS11CardState, reader: String? = nil, info: PKCS11ModuleInfo? = nil) {
        self.state = state
        self.reader = state == .ready ? reader.flatMap(Self.cleanReaderName) : nil
        self.info = info.flatMap { $0.module.isEmpty && $0.token.isEmpty ? nil : $0 }
    }

    /// A reader name as reported in the PKCS#11 slot description (blank padded, maybe cut off).
    static func cleanReaderName(_ name: String) -> String? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !name.contains(where: { $0.isNewline || $0.asciiValue.map { $0 < 0x20 } == true })
        else { return nil }
        return name
    }

    /// Text form used between the probe process and the app: the state, then the reader on line 2,
    /// the module and the card on lines 3 and 4.
    public var encoded: String {
        [state.encoded, reader ?? "", info?.module ?? "", info?.token ?? ""].joined(separator: "\n")
    }

    public init?(encoded: String) {
        let lines = encoded.split(separator: "\n", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
        guard let first = lines.first, let state = PKCS11CardState(encoded: first) else { return nil }
        let info = lines.count > 2 ? PKCS11ModuleInfo(module: lines[2], token: lines.count > 3 ? lines[3] : "") : nil
        self.init(state: state, reader: lines.count > 1 ? lines[1] : nil, info: info)
    }

    /// How long the app waits for the check process. A card driver can hang (e.g. in `C_Initialize`);
    /// the process is then stopped, so connecting never waits for it forever.
    public static let checkTimeout: Duration = .seconds(15)

    /// Error code of a check that was stopped after `checkTimeout`.
    public static let timedOutCode = -3
    /// Error code of a check whose output could not be read.
    public static let unreadableCode = -2
    /// Error code of a check that crashed (e.g. in the card driver).
    public static let crashedCode = -4

    /// The result reported by the check process.
    /// - Parameter signal: the signal that ended the process, if one did (`SIGKILL` is CardGate
    ///   stopping it after `checkTimeout`; any other is a crash); whatever it wrote is incomplete.
    public init(processOutput: String, signal: Int32?) {
        if let signal {
            self.init(state: .failed(code: signal == SIGKILL ? Self.timedOutCode : Self.crashedCode))
        } else {
            let text = processOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            self = Self(encoded: text) ?? Self(state: .failed(code: Self.unreadableCode))
        }
    }
}

public enum PKCS11Probe {
    /// Loads the module, looks at the tokens (no login, no PIN) and unloads it. Takes seconds with
    /// some middleware, so call it off the main thread – preferably in a separate process.
    public static func probe(module: String) -> PKCS11ProbeResult {
        var result = cg_card_probe(module)
        let state = PKCS11CardState(error: result.error, tokens: Int(result.tokens))
        let description = withUnsafeBytes(of: &result.slot_description) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
        }
        return PKCS11ProbeResult(state: state, reader: result.tokens == 1 ? description : nil, info: info(of: result))
    }

    static func info(of result: cg_card_probe_result) -> PKCS11ModuleInfo {
        var result = result
        func text<T>(_ field: inout T) -> String {
            withUnsafeBytes(of: &field) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) ?? "" }
        }
        func version(_ field: (UInt8, UInt8)) -> String { "\(field.0).\(field.1)" }
        // Without C_GetInfo (the module failed before it) there is nothing to tell, not even a version.
        let maker = text(&result.library_manufacturer)
        let name = text(&result.library_description)
        let library =
            maker.isEmpty && name.isEmpty
            ? "" : PKCS11ModuleInfo.describe(maker, name, [version(result.library_version)])
        let tokenMaker = text(&result.token_manufacturer)
        let tokenModel = text(&result.token_model)
        let token =
            tokenModel.isEmpty && tokenMaker.isEmpty
            ? ""
            : PKCS11ModuleInfo.describe(
                tokenMaker, tokenModel,
                [
                    "hardware \(version(result.token_hardware_version))",
                    "firmware \(version(result.token_firmware_version))",
                ])
        return PKCS11ModuleInfo(module: library, token: token)
    }

    /// PIN policy of the inserted card, or `nil` if no card is available.
    /// - Parameter certificateSHA1: the sign-in certificate (`FREERDP_SMARTCARD_CERT_SHA1`). With
    ///   several tokens (two cards, or one card with separate sign-in and signing PINs) the policy is
    ///   read from the token holding it.
    public static func pinPolicy(module: String, certificateSHA1: String? = nil) -> PINPolicy? {
        guard let wanted = certificateSHA1?.lowercased(), !wanted.isEmpty else {
            return pinPolicy(from: cg_card_probe(module))
        }
        let result = wanted.withCString { wanted in
            cg_card_probe_matching(
                module,
                { der, length, context in
                    guard let der, let context else { return 0 }
                    let sha1 = String(cString: context.assumingMemoryBound(to: CChar.self))
                    return PKCS11Probe.certificate(
                        UnsafeRawBufferPointer(start: der, count: Int(length)), hasSHA1: sha1)
                        ? 1 : 0
                }, UnsafeMutableRawPointer(mutating: wanted))
        }
        return pinPolicy(from: result)
    }

    /// Whether a DER certificate has the SHA-1 fingerprint (lowercase hex) CardGate selected.
    static func certificate(_ der: UnsafeRawBufferPointer, hasSHA1 sha1: String) -> Bool {
        Insecure.SHA1.hash(data: der).lowercaseHex == sha1
    }

    /// With several tokens and none found to hold the sign-in certificate, it is not known which one
    /// signs in. The length limits are then not claimed, but a warning about attempts of any token is
    /// shown – a warning too many is safe, a missing "last try" can lock the card. A locked other token
    /// does not block the PIN entry.
    static func pinPolicy(from result: cg_card_probe_result) -> PINPolicy? {
        guard result.error == 0, result.tokens > 0 else { return nil }
        guard result.tokens > 1, result.matched_token == 0 else {
            return PINPolicy(
                minLength: UInt(result.pin_min_length), maxLength: UInt(result.pin_max_length),
                flags: UInt(result.token_flags))
        }
        let combined = PINPolicy(minLength: 0, maxLength: 0, flags: UInt(result.any_token_flags))
        var policy = PINPolicy.unknown
        policy.countLow = combined.countLow
        policy.finalTry = combined.finalTry || combined.locked
        return policy
    }
}
