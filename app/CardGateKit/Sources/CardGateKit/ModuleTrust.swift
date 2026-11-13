import CryptoKit
public import Foundation
import Security

/// Whether a PKCS#11 module may be loaded. The module runs inside the RDP client, the PIN dialog and
/// the card check, so it sees the PIN: only a module from a verified publisher (Developer ID) is
/// loaded without asking. Any other (ad-hoc signed, unsigned, another certificate chain) needs the
/// user's explicit approval, which holds for exactly that file (path and SHA-256). A module whose
/// signature is broken (changed after signing) is never loaded.
public enum ModuleTrust: Equatable, Sendable {
    case trusted
    /// Not from a verified publisher and not approved yet (or the file changed since).
    case needsApproval(sha256: String)
    /// Signed, but changed since: it cannot be approved.
    case invalidSignature
    /// The file cannot be read to check it.
    case unreadable
}

/// The code signature of a module.
public enum ModuleSignature: Equatable, Sendable {
    /// Intact and signed with a Developer ID certificate.
    case developerID
    /// Intact, but ad-hoc or another certificate: says nothing about who made it.
    case unverified
    case unsigned
    /// Broken: the file was changed after it was signed.
    case invalid
}

/// Modules the user approved, by path, with the SHA-256 of the approved file.
public struct ModuleApprovals: Equatable, Sendable {
    /// Path → SHA-256 (hex); the form kept in the user defaults.
    public private(set) var hashes: [String: String]

    public init(hashes: [String: String] = [:]) {
        self.hashes = hashes
    }

    public func isApproved(path: String, sha256: String) -> Bool {
        hashes[path] == sha256
    }

    /// Approves the file; a module approved before at the same path is replaced.
    public mutating func approve(path: String, sha256: String) {
        hashes[path] = sha256
    }
}

/// Checks modules and remembers the result for each file until it changes, so switching
/// connections or activating the app does not check the signature or hash the file again.
public struct ModuleTrustChecker: Sendable {
    /// What identifies one version of a file: a replaced or rewritten module is checked again. The
    /// status change time cannot be set back (unlike the modification time), so it covers a file
    /// rewritten in place with the same size and its old modification time restored.
    public struct FileIdentity: Equatable, Sendable {
        public var size: Int64
        public var modified: timespec
        public var changed: timespec
        public var inode: UInt64
        public var device: Int32

        public init(size: Int64, modified: timespec, changed: timespec, inode: UInt64, device: Int32) {
            self.size = size
            self.modified = modified
            self.changed = changed
            self.inode = inode
            self.device = device
        }

        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.size == rhs.size && lhs.inode == rhs.inode && lhs.device == rhs.device
                && lhs.modified.tv_sec == rhs.modified.tv_sec && lhs.modified.tv_nsec == rhs.modified.tv_nsec
                && lhs.changed.tv_sec == rhs.changed.tv_sec && lhs.changed.tv_nsec == rhs.changed.tv_nsec
        }
    }

    private struct Checked: Sendable {
        var identity: FileIdentity
        var signature: ModuleSignature
        var sha256: String?
    }

    private var checked: [String: Checked] = [:]
    private let identity: @Sendable (String) -> FileIdentity?
    private let signature: @Sendable (String) -> ModuleSignature
    private let digest: @Sendable (String) -> String?

    public init(
        identity: @escaping @Sendable (String) -> FileIdentity? = ModuleTrustChecker.fileIdentity,
        signature: @escaping @Sendable (String) -> ModuleSignature = { CodeSignature.check(atPath: $0) },
        digest: @escaping @Sendable (String) -> String? = ModuleTrustChecker.sha256
    ) {
        self.identity = identity
        self.signature = signature
        self.digest = digest
    }

    /// - Parameter path: the path the module is loaded from; the approval is kept for it. The file it
    ///   leads to (through symbolic links) is what is checked, so a link pointed elsewhere is noticed.
    public mutating func trust(ofModuleAt path: String, approvals: ModuleApprovals) -> ModuleTrust {
        let file = Self.resolved(path)
        guard let current = identity(file) else { return .unreadable }
        var entry = checked[path] ?? Checked(identity: current, signature: signature(file))
        if entry.identity != current {
            entry = Checked(identity: current, signature: signature(file))
        }
        defer { checked[path] = entry }
        switch entry.signature {
        case .developerID: return .trusted
        case .invalid: return .invalidSignature
        case .unverified, .unsigned: break
        }
        if entry.sha256 == nil { entry.sha256 = digest(file) }
        guard let sha256 = entry.sha256 else { return .unreadable }
        return approvals.isApproved(path: path, sha256: sha256) ? .trusted : .needsApproval(sha256: sha256)
    }

    /// The file a path leads to, with symbolic links resolved (the path itself if it cannot be).
    static func resolved(_ path: String) -> String {
        guard let real = realpath(path, nil) else { return path }
        defer { free(real) }
        return String(cString: real)
    }

    /// Identity of the file itself (`stat` follows symbolic links).
    @Sendable public static func fileIdentity(_ path: String) -> FileIdentity? {
        var info = stat()
        guard stat(path, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return nil }
        return FileIdentity(
            size: info.st_size, modified: info.st_mtimespec, changed: info.st_ctimespec, inode: info.st_ino,
            device: info.st_dev)
    }

    @Sendable public static func sha256(_ path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(filePath: path), options: .mappedIfSafe) else { return nil }
        return SHA256.hash(data: data).lowercaseHex
    }
}

/// Code signature checks of libraries loaded into the RDP client (PKCS#11 modules).
public enum CodeSignature {
    /// Checks the signature for all architectures. An intact signature alone proves nothing (on
    /// Apple silicon all code is signed, at least ad-hoc); only a Developer ID names the publisher.
    /// Only a signature that no longer matches the code or is damaged counts as broken; any other
    /// problem (e.g. an unusual layout the strict check refuses) is treated like an unverified module.
    public static func check(atPath path: String) -> ModuleSignature {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(URL(filePath: path) as CFURL, [], &code) == errSecSuccess, let code,
            SecRequirementCreateWithString(developerID as CFString, [], &requirement) == errSecSuccess
        else { return .unverified }
        // One validation: the signature first, then the requirement.
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate)
        switch SecStaticCodeCheckValidity(code, flags, requirement) {
        case errSecSuccess: return .developerID
        case errSecCSUnsigned: return .unsigned
        // The code no longer matches its signature, or the signature itself is damaged.
        case errSecCSSignatureFailed, errSecCSSignatureInvalid: return .invalid
        default: return .unverified  // e.g. `errSecCSReqFailed`: intact, but not a Developer ID
        }
    }

    /// Apple's anchor, the Developer ID intermediate and a Developer ID Application leaf.
    static let developerID =
        "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists "
        + "and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
}

/// Why no PKCS#11 module is used although one is set or installed (it is then not loaded).
public enum ModuleProblem: Equatable, Sendable {
    /// The module set in the connection does not exist or cannot be read.
    case configuredMissing(path: String)
    /// Not from a verified publisher; loaded only after the user approves it (`ModuleTrust`).
    case needsApproval(path: String, sha256: String)
    /// Changed after it was signed: never loaded.
    case invalidSignature(path: String)
    case unreadable(path: String)

    /// The module to load and what keeps another one from being used.
    /// - Parameters:
    ///   - configured: the module set in the connection (`nil` or empty: automatic).
    ///   - resolved: what `PKCS11ModuleLocator.resolve` found for it.
    ///   - trust: checks a module (`ModuleTrustChecker.trust`).
    public static func evaluate(
        configured: String?, resolved: String?, trust: (String) -> ModuleTrust
    ) -> (module: String?, problem: ModuleProblem?) {
        let configured = configured.flatMap { $0.isEmpty ? nil : $0 }
        guard let path = resolved else {
            return (nil, configured.map { .configuredMissing(path: $0) })
        }
        switch trust(path) {
        case .trusted: return (path, nil)
        case .needsApproval(let sha256): return (nil, .needsApproval(path: path, sha256: sha256))
        case .invalidSignature: return (nil, .invalidSignature(path: path))
        case .unreadable: return (nil, .unreadable(path: path))
        }
    }
}

extension ModuleApprovals {
    /// Key of the approvals in the app's user defaults.
    public static let defaultsKey = "ApprovedPKCS11Modules"

    /// The approvals the app saved in its own defaults domain. `UserDefaults` lookups would also
    /// take a value from the command line (`-ApprovedPKCS11Modules …`), which must not approve a module.
    public init(savedIn defaults: UserDefaults, domain: String) {
        let saved = defaults.persistentDomain(forName: domain)?[Self.defaultsKey] as? [String: String]
        self.init(hashes: saved ?? [:])
    }

    public func save(in defaults: UserDefaults) {
        defaults.set(hashes, forKey: Self.defaultsKey)
    }
}
