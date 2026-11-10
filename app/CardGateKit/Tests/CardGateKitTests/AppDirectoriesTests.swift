import CardGateKit
import Foundation
import Testing

struct AppDirectoriesTests {
    @Test func usesApplicationSupportByDefault() throws {
        let url = try AppDirectories.data(environment: [:])
        #expect(url.path(percentEncoded: false).hasSuffix("/Library/Application Support/CardGate/"))
    }

    @Test func usesTheOverrideForTests() throws {
        let url = try AppDirectories.data(environment: [AppDirectories.dataDirectoryVariable: "/tmp/cg-ui-test"])
        #expect(url.path(percentEncoded: false) == "/tmp/cg-ui-test/")
    }

    @Test func ignoresARelativeOverride() throws {
        let url = try AppDirectories.data(environment: [AppDirectories.dataDirectoryVariable: "relative/dir"])
        #expect(url.path(percentEncoded: false).hasSuffix("/Application Support/CardGate/"))
    }
}
