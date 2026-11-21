import XCTest

/// Steps the tests share: starting the app and doing what a user does.
extension CardGateUITests {
    func launch(language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CARDGATE_DATA_DIR"] = dataDirectory?.path(percentEncoded: false)
        // The example gateways never answer; the background port check would only add a warning.
        app.launchEnvironment["CARDGATE_NO_GATEWAY_CHECK"] = "1"
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", ["en": "en_US", "cs": "cs_CZ", "sk": "sk_SK"][language] ?? language,
            // No update check prompt and no support offer during tests.
            "-SUEnableAutomaticChecks", "NO",
            "-DonationPromptDisabled", "YES",
        ]
        app.launch()
        return app
    }

    /// Clicks a menu bar item (by title, as in the English menus).
    func choose(_ app: XCUIApplication, menu: String, item: String) {
        let bar = app.menuBars.menuBarItems[menu]
        bar.click()
        bar.menuItems[item].click()
    }

    /// Types into the PKCS#11 module field, the last text field of the form (in the Advanced group,
    /// below the visible part): opens the group and scrolls to the field.
    func typeModule(_ app: XCUIApplication, _ text: String) {
        let module = app.textFields["profile.module"]
        if !module.exists {
            let advanced = app.buttons["profile.advanced"]
            XCTAssertTrue(advanced.waitForExistence(timeout: 5))
            scrollIntoView(app, advanced)
            advanced.click()
            XCTAssertTrue(module.waitForExistence(timeout: 5))
        }
        scrollIntoView(app, module)
        module.click()
        module.typeText(text)
        XCTAssertEqual(module.value as? String, text)
    }

    /// Scrolls the connection sheet until `element` is in its visible part: XCUITest does not
    /// scroll the form on macOS, a click below it lands on the buttons under the form.
    func scrollIntoView(_ app: XCUIApplication, _ element: XCUIElement) {
        let form = app.sheets.scrollViews.firstMatch
        for _ in 0..<20 where !form.frame.contains(element.frame) {
            form.scroll(byDeltaX: 0, deltaY: -50)
        }
        XCTAssertTrue(form.frame.contains(element.frame), "\(element) is in view")
    }

    /// Opens the connection editor from the welcome screen.
    func openNewConnection(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["Set Up Connection"].waitForExistence(timeout: 10))
        app.buttons["Set Up Connection"].click()
        XCTAssertTrue(app.textFields["profile.computer"].waitForExistence(timeout: 5))
    }

    /// Fills the connection sheet and saves it.
    func addConnection(
        _ app: XCUIApplication, name: String, computer: String, gateway: String? = "rdg.example.com",
        module: String? = nil
    ) {
        let nameField = app.textFields["profile.name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.click()
        nameField.typeKey("a", modifierFlags: .command)
        nameField.typeText(name)
        app.textFields["profile.computer"].click()
        app.textFields["profile.computer"].typeText(computer)
        if let gateway {
            app.textFields["profile.gateway"].click()
            app.textFields["profile.gateway"].typeText(gateway)
        }
        if let module { typeModule(app, module) }
        app.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts[name].waitForExistence(timeout: 5))
    }

    func writeFile(_ name: String, _ contents: String) throws -> URL {
        let url = try XCTUnwrap(dataDirectory).appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }

    /// Picks a file in the open panel by typing its path (⌘⇧G).
    func importFile(_ app: XCUIApplication, _ url: URL) {
        app.typeKey("o", modifierFlags: .command)
        let panel = app.sheets.firstMatch.exists ? app.sheets.firstMatch : app.dialogs.firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        app.typeKey("g", modifierFlags: [.command, .shift])
        app.typeText(url.path(percentEncoded: false))
        app.typeKey(.return, modifierFlags: [])
        sleep(1)
        app.typeKey(.return, modifierFlags: [])
    }
}
