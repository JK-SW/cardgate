// swift-tools-version: 6.2
// Application logic of CardGate without any UI, so it can be unit tested with `swift test`.
import PackageDescription

let strict: [SwiftSetting] = [
    .treatAllWarnings(as: .error),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "CardGateKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "CardGateKit", targets: ["CardGateKit"])
    ],
    targets: [
        // Minimal PKCS#11 access (public domain pkcs11.h) to check a card without a PIN.
        .target(name: "CPKCS11"),
        .target(name: "CardGateKit", dependencies: ["CPKCS11"], swiftSettings: strict),
        .testTarget(name: "CardGateKitTests", dependencies: ["CardGateKit"], swiftSettings: strict),
    ],
    swiftLanguageModes: [.v6]
)
