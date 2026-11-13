public import Foundation

/// Where CardGate keeps its data (connections, FreeRDP configuration).
public enum AppDirectories {
    /// Overrides the data directory in Debug builds; the UI tests run each test with an empty one,
    /// so they never touch the user's connections. A release build ignores it: the connections
    /// (including the card module path) always come from the user's own directory.
    public static let dataDirectoryVariable = "CARDGATE_DATA_DIR"

    /// `~/Library/Application Support/CardGate`, or (Debug builds only) the directory in
    /// `CARDGATE_DATA_DIR`.
    public static func data(environment: [String: String] = ProcessInfo.processInfo.environment) throws -> URL {
        #if DEBUG
            if let path = environment[dataDirectoryVariable], path.hasPrefix("/") {
                return URL(filePath: path, directoryHint: .isDirectory)
            }
        #endif
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return support.appending(path: "CardGate", directoryHint: .isDirectory)
    }
}
