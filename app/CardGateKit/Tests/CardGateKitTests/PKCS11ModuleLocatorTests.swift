import CardGateKit
import Testing

struct PKCS11ModuleLocatorTests {
    let first = PKCS11ModuleLocator.Middleware(name: "First", modulePath: "/a/first.dylib", downloadURL: nil)
    let second = PKCS11ModuleLocator.Middleware(name: "Second", modulePath: "/b/second.so", downloadURL: nil)

    func locator(existing: Set<String>) -> PKCS11ModuleLocator {
        PKCS11ModuleLocator(candidates: [first, second], isUsable: { existing.contains($0) })
    }

    @Test func picksFirstInstalled() {
        #expect(locator(existing: [first.modulePath, second.modulePath]).resolve(configured: nil) == first.modulePath)
        #expect(locator(existing: [second.modulePath]).resolve(configured: nil) == second.modulePath)
    }

    @Test func nothingInstalled() {
        let locator = locator(existing: [])
        #expect(locator.resolve(configured: nil) == nil)
        #expect(locator.installed.isEmpty)
    }

    @Test func explicitModuleWins() {
        #expect(
            locator(existing: ["/custom.dylib", first.modulePath]).resolve(configured: "/custom.dylib")
                == "/custom.dylib")
    }

    @Test func missingExplicitModuleIsNotReplaced() {
        #expect(locator(existing: [first.modulePath]).resolve(configured: "/missing.dylib") == nil)
    }

    @Test func emptyExplicitModuleMeansAutomatic() {
        #expect(locator(existing: [second.modulePath]).resolve(configured: "") == second.modulePath)
    }

    @Test func knownMiddlewareHasAbsolutePaths() {
        #expect(!PKCS11ModuleLocator.knownMiddleware.isEmpty)
        #expect(PKCS11ModuleLocator.knownMiddleware.allSatisfy { $0.modulePath.hasPrefix("/") })
    }
}
