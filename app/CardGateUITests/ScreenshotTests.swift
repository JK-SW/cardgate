import XCTest

/// Walks through the screens shown in the user guides; `scripts/screenshots.sh` takes the
/// pictures. Skipped unless the script runs it (`CARDGATE_SCREENSHOTS_LANGUAGE`). The app runs as a
/// debug build with a demo card (`CARDGATE_DEMO_CARD`), so no real name appears.
@MainActor
final class ScreenshotTests: XCTestCase {
    private var dataDirectory: URL?

    override func setUp() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CARDGATE_SCREENSHOTS_LANGUAGE"] != nil else {
            throw XCTSkip("screenshots are taken by scripts/screenshots.sh")
        }
        let data = FileManager.default.temporaryDirectory.appending(path: "CardGateScreenshots-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
        dataDirectory = data
    }

    override func tearDown() async throws {
        XCUIApplication().terminate()
        if let dataDirectory { try? FileManager.default.removeItem(at: dataDirectory) }
    }

    /// Asks scripts/screenshot-server.swift to capture the frontmost CardGate window and waits
    /// until it has (the test runner is sandboxed and cannot take or write the picture itself).
    private func capture(_ name: String) {
        sleep(1)  // let animations finish
        let center = DistributedNotificationCenter.default()
        let captured = expectation(description: name)
        let observer = center.addObserver(
            forName: Notification.Name("io.github.jk-sw.cardgate.screenshots.done"), object: name, queue: .main
        ) { _ in captured.fulfill() }
        center.postNotificationName(
            Notification.Name("io.github.jk-sw.cardgate.screenshots.request"), object: name, userInfo: nil,
            deliverImmediately: true)
        wait(for: [captured], timeout: 15)
        center.removeObserver(observer)
    }

    func testGuideScreens() throws {
        let environment = ProcessInfo.processInfo.environment
        let language = environment["CARDGATE_SCREENSHOTS_LANGUAGE"] ?? "en"
        let name = environment["CARDGATE_SCREENSHOTS_CONNECTION"] ?? "Office"

        let app = XCUIApplication()
        app.launchEnvironment["CARDGATE_DATA_DIR"] = dataDirectory?.path(percentEncoded: false)
        app.launchEnvironment["CARDGATE_APPEARANCE"] = "light"
        app.launchEnvironment["CARDGATE_DEMO_CARD"] = environment["CARDGATE_DEMO_CARD"] ?? "Jane Doe"
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", ["en": "en_US", "cs": "cs_CZ", "sk": "sk_SK"][language] ?? language,
            "-SUEnableAutomaticChecks", "NO",
            "-DonationPromptDisabled", "YES",
        ]
        app.launch()

        let setUp = app.buttons.element(boundBy: 0)
        XCTAssertTrue(setUp.waitForExistence(timeout: 10))
        capture("welcome")

        app.typeKey("n", modifierFlags: .command)
        let nameField = app.textFields["profile.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText(name)
        app.textFields["profile.computer"].click()
        app.textFields["profile.computer"].typeText("pc01.example.com")
        app.textFields["profile.gateway"].click()
        app.textFields["profile.gateway"].typeText("rdg.example.com")
        app.textFields["profile.name"].click()  // no blinking cursor in the address fields
        capture("connection-settings")

        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["connect"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["connect"].isEnabled, "the demo card is ready")
        capture("main-window")

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.switches["settings.automaticUpdates"].waitForExistence(timeout: 5))
        capture("settings")
    }
}
