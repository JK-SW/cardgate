import CardGateKit
import Foundation
import Testing

/// Runs against the assembled FreeRDP helper when `CARDGATE_HELPER` points to its directory
/// (`build/helper`, set by scripts/test.sh); skipped otherwise.
struct HelperIntegrationTests {
    static let helper = ProcessInfo.processInfo.environment["CARDGATE_HELPER"].map { URL(filePath: $0) }

    /// The parser depends on these texts; a FreeRDP update must not remove them.
    @Test(.enabled(if: helper != nil), arguments: SessionLogParser.logMarkers)
    func clientContainsLogMarker(_ marker: String) throws {
        let directory = try #require(Self.helper)
        let binaries =
            [directory.appending(path: FreeRDPCommand.bundledClientPath)]
            + (try FileManager.default.contentsOfDirectory(
                at: directory.appending(path: "Frameworks"), includingPropertiesForKeys: nil))
        let needle = Data(marker.utf8)
        let found = try binaries.contains { try Data(contentsOf: $0).range(of: needle) != nil }
        #expect(found, "FreeRDP no longer logs '\(marker)'")
    }

    /// Every option CardGate passes must be accepted by the client's command line parser.
    @Test(.enabled(if: helper != nil), arguments: [DisplaySettings.Mode.window, .fullScreen, .allDisplays])
    func clientAcceptsGeneratedArguments(_ mode: DisplaySettings.Mode) throws {
        let directory = try #require(Self.helper)
        let config = FreeRDPClientConfig(directory: FileManager.default.temporaryDirectory.appending(path: "cg-it"))
        let profile = ConnectionProfile(
            name: "x", computer: try HostAddress(parsing: "127.0.0.1:1"),
            gateway: try HostAddress(parsing: "127.0.0.1:1"), display: .init(mode: mode))
        let command = try FreeRDPCommand(
            executable: directory.appending(path: FreeRDPCommand.bundledClientPath), profile: profile,
            pkcs11Module: "/nonexistent/module.dylib", config: config,
            screen: ScreenMetrics(visibleSize: .init(width: 1440, height: 900), scale: 2),
            smartCardReader: "Example USB Reader 0")

        let process = Process()
        process.executableURL = command.executable
        // /help-like check: parse everything, then stop before connecting.
        process.arguments = command.arguments + ["/buildconfig"]
        process.environment = command.environment.merging(["HOME": NSHomeDirectory()]) { $1 }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(bytes: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "client rejected the arguments: \(output.suffix(800))")
        #expect(output.contains("Build configuration"))
    }
}
