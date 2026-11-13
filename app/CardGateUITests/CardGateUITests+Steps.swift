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

    /// Types into the PKCS#11 module field, the last text field of the form (below the visible
    /// part): Tab from the gateway field moves the focus there, as it would for the user.
    func typeModule(_ app: XCUIApplication, _ text: String) {
        app.textFields["profile.gateway"].click()
        app.typeKey(.tab, modifierFlags: [])
        app.typeText(text)
        XCTAssertEqual(app.textFields["profile.module"].value as? String, text)
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
