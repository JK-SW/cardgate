import CardGateKit
import Foundation
import Testing

struct AppDirectoriesTests {
    @Test func usesApplicationSupportByDefault() throws {
        let url = try AppDirectories.data(environment: [:])
        #expect(url.path(percentEncoded: false).hasSuffix("/Library/Application Support/CardGate/"))
    }

    /// Only Debug builds (UI tests) honour the override; a release build always uses the user's data.
    @Test func usesTheOverrideOnlyInDebugBuilds() throws {
        let url = try AppDirectories.data(environment: [AppDirectories.dataDirectoryVariable: "/tmp/cg-ui-test"])
        #if DEBUG
            #expect(url.path(percentEncoded: false) == "/tmp/cg-ui-test/")
        #else
            #expect(url.path(percentEncoded: false).hasSuffix("/Application Support/CardGate/"))
        #endif
    }

    @Test func ignoresARelativeOverride() throws {
        let url = try AppDirectories.data(environment: [AppDirectories.dataDirectoryVariable: "relative/dir"])
        #expect(url.path(percentEncoded: false).hasSuffix("/Application Support/CardGate/"))
    }
}
