import Foundation
import Synchronization
import Testing

@testable import CardGateKit

struct ModuleTrustTests {
    static let path = "/usr/local/lib/example/pkcs11.dylib"
    static let version1 = ModuleTrustChecker.FileIdentity(
        size: 10, modified: timespec(tv_sec: 1, tv_nsec: 0), changed: timespec(tv_sec: 1, tv_nsec: 0), inode: 1,
        device: 1)

    /// Counts the expensive checks, to see what the cache saves.
    final class Calls: Sendable {
        let signature = Atomic(0)
        let digest = Atomic(0)
    }

    static func checker(
        identity: ModuleTrustChecker.FileIdentity? = version1, signature: ModuleSignature, sha256: String? = "aa",
        calls: Calls = Calls()
    ) -> ModuleTrustChecker {
        ModuleTrustChecker(
            identity: { _ in identity },
            signature: { _ in
                calls.signature.add(1, ordering: .relaxed)
                return signature
            },
            digest: { _ in
                calls.digest.add(1, ordering: .relaxed)
                return sha256
            })
    }

    @Test func verifiedPublisherIsTrustedWithoutHashing() {
        let calls = Calls()
        var checker = Self.checker(signature: .developerID, calls: calls)
        #expect(checker.trust(ofModuleAt: Self.path, approvals: .init()) == .trusted)
        #expect(calls.digest.load(ordering: .relaxed) == 0)
    }

    @Test(arguments: [ModuleSignature.unverified, .unsigned])
    func otherModulesNeedApprovalOfThatFile(_ signature: ModuleSignature) {
        var checker = Self.checker(signature: signature, sha256: "aa")
        #expect(checker.trust(ofModuleAt: Self.path, approvals: .init()) == .needsApproval(sha256: "aa"))

        var approvals = ModuleApprovals()
        approvals.approve(path: Self.path, sha256: "aa")
        #expect(checker.trust(ofModuleAt: Self.path, approvals: approvals) == .trusted)

        // The approval belongs to the file at that path: another file or another path is not approved.
        #expect(checker.trust(ofModuleAt: "/tmp/other.dylib", approvals: approvals) == .needsApproval(sha256: "aa"))
        var changed = Self.checker(signature: signature, sha256: "bb")
        #expect(changed.trust(ofModuleAt: Self.path, approvals: approvals) == .needsApproval(sha256: "bb"))
    }

    /// A module changed after it was signed is never loaded, not even when the user would approve it.
    @Test func brokenSignatureCannotBeApproved() {
        var checker = Self.checker(signature: .invalid, sha256: "aa")
        var approvals = ModuleApprovals()
        approvals.approve(path: Self.path, sha256: "aa")
        #expect(checker.trust(ofModuleAt: Self.path, approvals: approvals) == .invalidSignature)
    }

    @Test func unreadableFileIsNeverTrusted() {
        var missing = Self.checker(identity: nil, signature: .developerID)
        #expect(missing.trust(ofModuleAt: Self.path, approvals: .init()) == .unreadable)
        var noDigest = Self.checker(signature: .unsigned, sha256: nil)
        #expect(noDigest.trust(ofModuleAt: Self.path, approvals: .init()) == .unreadable)
    }

    @Test func checksAgainOnlyWhenTheFileChanges() {
        let calls = Calls()
        let identity = Mutex(Self.version1)
        var checker = ModuleTrustChecker(
            identity: { _ in identity.withLock { $0 } },
            signature: { _ in
                calls.signature.add(1, ordering: .relaxed)
                return .unverified
            },
            digest: { _ in
                calls.digest.add(1, ordering: .relaxed)
                return "aa"
            })
        for _ in 0..<3 { _ = checker.trust(ofModuleAt: Self.path, approvals: .init()) }
        #expect(calls.signature.load(ordering: .relaxed) == 1)
        #expect(calls.digest.load(ordering: .relaxed) == 1)

        // Rewritten in place with the same size and modification time: the status change time differs.
        identity.withLock { $0.changed.tv_nsec = 5 }
        _ = checker.trust(ofModuleAt: Self.path, approvals: .init())
        #expect(calls.signature.load(ordering: .relaxed) == 2)
        #expect(calls.digest.load(ordering: .relaxed) == 2)
    }

    @Test func hashesAndIdentifiesRealFiles() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cg-module-\(UUID().uuidString)")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let path = url.path(percentEncoded: false)
        #expect(
            ModuleTrustChecker.sha256(path) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(ModuleTrustChecker.fileIdentity(path)?.size == 3)
        #expect(ModuleTrustChecker.fileIdentity("/nonexistent/module.dylib") == nil)
        #expect(ModuleTrustChecker.fileIdentity(FileManager.default.temporaryDirectory.path) == nil)  // a folder
        // Not code at all: nothing signed, so it can be approved like any unsigned module.
        #expect(CodeSignature.check(atPath: path) == .unsigned)
    }

    /// A symbolic link is checked as the file it leads to: pointing it elsewhere is noticed.
    @Test func followsSymbolicLinks() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "cg-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "first.dylib")
        let second = directory.appending(path: "second.dylib")
        let link = directory.appending(path: "module.dylib")
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: first)

        var checker = ModuleTrustChecker(signature: { _ in .unsigned })
        let path = link.path(percentEncoded: false)
        let before = checker.trust(ofModuleAt: path, approvals: .init())
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: second)
        let after = checker.trust(ofModuleAt: path, approvals: .init())
        #expect(before == .needsApproval(sha256: try #require(ModuleTrustChecker.sha256(first.path))))
        #expect(after == .needsApproval(sha256: try #require(ModuleTrustChecker.sha256(second.path))))
    }

    /// An ad-hoc signature is intact but says nothing about who made the library; changing the code
    /// afterwards breaks it.
    @Test func adHocAndBrokenSignatures() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "cg-adhoc-\(UUID().uuidString).dylib")
        defer { try? FileManager.default.removeItem(at: url) }
        // One architecture only, so the byte changed below is inside the signed code whatever the
        // layout of the universal original.
        let architecture = try #require(
            try Self.run("/usr/bin/lipo", ["-archs", "/usr/lib/dyld"]).split(separator: " ").first)
        try Self.run(
            "/usr/bin/lipo",
            ["/usr/lib/dyld", "-thin", String(architecture), "-output", url.path(percentEncoded: false)])
        try Self.run("/usr/bin/codesign", ["-f", "-s", "-", url.path(percentEncoded: false)])
        #expect(CodeSignature.check(atPath: url.path(percentEncoded: false)) == .unverified)

        // A byte in the first third: the code, well before the signature at the end of the file.
        let size = try #require(ModuleTrustChecker.fileIdentity(url.path(percentEncoded: false))?.size)
        let offset = UInt64(size / 3)
        let handle = try FileHandle(forUpdating: url)
        try handle.seek(toOffset: offset)
        let byte = try #require(try handle.read(upToCount: 1)).first ?? 0
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: Data([byte ^ 0xFF]))
        try handle.close()
        #expect(CodeSignature.check(atPath: url.path(percentEncoded: false)) == .invalid)
    }

    /// Runs a tool and returns its output (trimmed).
    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: tool)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "\(tool) \(arguments) failed")
        return (String(bytes: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// On a Mac with ProID+ installed: its module is signed with a Developer ID (no approval needed).
    @Test(.enabled(if: FileManager.default.fileExists(atPath: PKCS11ModuleLocator.knownMiddleware[0].modulePath)))
    func installedProIDModuleHasADeveloperID() {
        #expect(CodeSignature.check(atPath: PKCS11ModuleLocator.knownMiddleware[0].modulePath) == .developerID)
    }
}

struct ModuleProblemTests {
    let path = "/usr/local/lib/example/pkcs11.dylib"

    @Test func trustedModuleIsUsed() {
        let result = ModuleProblem.evaluate(configured: nil, resolved: path) { _ in .trusted }
        #expect(result.module == path)
        #expect(result.problem == nil)
    }

    /// A module set in the connection that is not there is named, not reported as missing software.
    @Test func missingConfiguredModule() {
        let missing = ModuleProblem.evaluate(configured: "/opt/x.dylib", resolved: nil) { _ in .trusted }
        #expect(missing.module == nil)
        #expect(missing.problem == .configuredMissing(path: "/opt/x.dylib"))
        // Nothing set and nothing installed: no module problem (the card software is missing).
        #expect(ModuleProblem.evaluate(configured: "", resolved: nil) { _ in .trusted }.problem == nil)
        #expect(ModuleProblem.evaluate(configured: nil, resolved: nil) { _ in .trusted }.problem == nil)
    }

    @Test func untrustedModulesAreNotLoaded() {
        let cases: [(ModuleTrust, ModuleProblem)] = [
            (.needsApproval(sha256: "aa"), .needsApproval(path: path, sha256: "aa")),
            (.invalidSignature, .invalidSignature(path: path)),
            (.unreadable, .unreadable(path: path)),
        ]
        for (trust, problem) in cases {
            let result = ModuleProblem.evaluate(configured: path, resolved: path) { _ in trust }
            #expect(result.module == nil)
            #expect(result.problem == problem)
        }
    }
}

/// Approvals come only from what the app saved, never from the command line.
@Suite(.serialized)
struct ModuleApprovalsStorageTests {
    @Test func savedApprovalsAreRead() throws {
        let domain = "cardgate-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        var approvals = ModuleApprovals()
        approvals.approve(path: "/opt/x.dylib", sha256: "aa")
        approvals.save(in: defaults)
        #expect(ModuleApprovals(savedIn: defaults, domain: domain) == approvals)
    }

    @Test func commandLineCannotApprove() throws {
        let domain = "cardgate-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer { defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain) }
        var injected = arguments
        injected[ModuleApprovals.defaultsKey] = ["/opt/evil.dylib": "aa"]
        defaults.setVolatileDomain(injected, forName: UserDefaults.argumentDomain)

        // A plain lookup would take it ...
        #expect(defaults.dictionary(forKey: ModuleApprovals.defaultsKey) != nil)
        // ... the approvals do not.
        #expect(ModuleApprovals(savedIn: defaults, domain: domain).hashes.isEmpty)
    }
}
