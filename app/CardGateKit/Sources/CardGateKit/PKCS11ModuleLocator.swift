public import Foundation

/// Finds the PKCS#11 module of an installed smart card middleware.
public struct PKCS11ModuleLocator: Sendable {
    /// A known middleware and where its PKCS#11 module is installed.
    public struct Middleware: Equatable, Sendable {
        public let name: String
        public let modulePath: String
        public let downloadURL: URL?

        public init(name: String, modulePath: String, downloadURL: URL?) {
            self.name = name
            self.modulePath = modulePath
            self.downloadURL = downloadURL
        }
    }

    /// Middleware probed in this order.
    public static let knownMiddleware: [Middleware] = [
        .init(
            name: "ProID+",
            modulePath: "/usr/local/lib/ProIDPlus/libproidqcm11.dylib",
            downloadURL: URL(string: "https://proid.cz")),
        .init(
            name: "OpenSC",
            modulePath: "/Library/OpenSC/lib/opensc-pkcs11.so",
            downloadURL: URL(string: "https://github.com/OpenSC/OpenSC/releases")),
    ]

    private let candidates: [Middleware]
    private let isUsable: @Sendable (String) -> Bool

    public init(
        candidates: [Middleware] = Self.knownMiddleware,
        isUsable: @escaping @Sendable (String) -> Bool = { FileManager.default.isReadableFile(atPath: $0) }
    ) {
        self.candidates = candidates
        self.isUsable = isUsable
    }

    /// The module to use: the explicitly configured one if usable, otherwise the first installed one.
    public func resolve(configured: String?) -> String? {
        if let configured, !configured.isEmpty {
            return isUsable(configured) ? configured : nil
        }
        return installed.first?.modulePath
    }

    /// All known middleware that is installed on this Mac.
    public var installed: [Middleware] {
        candidates.filter { isUsable($0.modulePath) }
    }
}
