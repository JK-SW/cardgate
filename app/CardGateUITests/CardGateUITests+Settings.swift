import XCTest

/// Settings of a connection in the editor sheet.
extension CardGateUITests {
    func testWindowSizeIsOnlyOfferedForAWindow() {
        let app = launch()
        openNewConnection(app)
        // A new connection opens in full screen.
        XCTAssertEqual(app.popUpButtons["profile.displayMode"].value as? String, "Full screen")
        XCTAssertFalse(app.popUpButtons["profile.windowSize"].exists)
        app.popUpButtons["profile.displayMode"].click()
        app.menuItems["Window"].click()
        XCTAssertTrue(app.popUpButtons["profile.windowSize"].waitForExistence(timeout: 5))
        app.popUpButtons["profile.displayMode"].click()
        app.menuItems["Full screen"].click()
        XCTAssertFalse(app.popUpButtons["profile.windowSize"].exists)
    }

    /// The display chosen for full screen shows while it is not connected (also with one display) and
    /// can be changed back to the main display.
    func testFullScreenDisplayCanBeSetToTheMainDisplay() throws {
        _ = try writeFile(
            "profiles.json",
            #"{"version":1,"profiles":[{"id":"6F1C2A52-8B39-4B79-9A43-2B7D4D0B5E10","name":"Office","#
                + #""computer":"pc01.example.com","gateway":"rdg.example.com","#
                + #""display":{"mode":"fullScreen","fullScreenDisplay":{"key":"1-2-3","name":"Projector"}}}]}"#)
        let app = launch()
        XCTAssertTrue(app.buttons["connection.edit"].waitForExistence(timeout: 10))
        app.buttons["connection.edit"].click()
        let display = app.popUpButtons["profile.fullScreenDisplay"]
        XCTAssertTrue(display.waitForExistence(timeout: 5))
        XCTAssertEqual(display.value as? String, "Projector (not connected)")
        display.click()
        app.menuItems["Main display"].click()
        XCTAssertEqual(display.value as? String, "Main display")
        app.buttons["Save"].click()

        app.buttons["connection.edit"].click()
        XCTAssertTrue(app.popUpButtons["profile.displayMode"].waitForExistence(timeout: 5))
        // With one display the choice is gone, with more it shows the main display.
        if display.exists {
            XCTAssertEqual(display.value as? String, "Main display")
        }
        XCTAssertFalse(app.menuItems["Projector (not connected)"].exists)
    }

    /// The scale is offered in every display mode and saved.
    func testScaleIsSaved() {
        let app = launch()
        openNewConnection(app)
        let scale = app.popUpButtons["profile.scale"]
        XCTAssertEqual(scale.value as? String, "Automatic")
        app.popUpButtons["profile.displayMode"].click()
        app.menuItems["Full screen"].click()
        // With several displays "Show on" appears above it and moves it down.
        scrollIntoView(app, scale)
        scale.click()
        // The percent format depends on the region ("150%" or "150 %").
        let percent = app.menuItems.matching(NSPredicate(format: "title BEGINSWITH '150'")).firstMatch
        XCTAssertTrue(percent.waitForExistence(timeout: 5))
        percent.click()
        addConnection(app, name: "Office", computer: "pc01.example.com")

        app.buttons["connection.edit"].click()
        XCTAssertTrue(scale.waitForExistence(timeout: 5))
        XCTAssertTrue((scale.value as? String)?.hasPrefix("150") == true)
    }

    func testSharingSettingsAreSaved() {
        let app = launch()
        openNewConnection(app)
        let clipboard = app.switches["profile.clipboard"]
        let audio = app.switches["profile.audio"]
        XCTAssertEqual(clipboard.value as? Int, 1)
        XCTAssertEqual(audio.value as? Int, 1)
        clipboard.click()
        audio.click()
        XCTAssertEqual(clipboard.value as? Int, 0)
        XCTAssertEqual(audio.value as? Int, 0)
        addConnection(app, name: "Office", computer: "pc01.example.com")

        app.buttons["connection.edit"].click()
        XCTAssertTrue(clipboard.waitForExistence(timeout: 5))
        XCTAssertEqual(clipboard.value as? Int, 0)
        XCTAssertEqual(audio.value as? Int, 0)
    }

    /// The advanced settings are closed for a new connection and open for one that uses them.
    func testWindowsSignInIsSavedInTheAdvancedSettings() {
        let app = launch()
        openNewConnection(app)
        let signIn = app.popUpButtons["profile.windowsSignIn"]
        XCTAssertFalse(signIn.exists)
        app.buttons["profile.advanced"].click()
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        XCTAssertEqual(signIn.value as? String, "With the card")
        scrollIntoView(app, signIn)
        signIn.click()
        let password = app.menuItems["With user name and password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5))
        password.click()
        addConnection(app, name: "Office", computer: "pc01.example.com")

        app.buttons["connection.edit"].click()
        XCTAssertTrue(signIn.waitForExistence(timeout: 5))
        XCTAssertEqual(signIn.value as? String, "With user name and password")
    }

    /// Keeping an idle session active is not offered until the hidden setting is turned on.
    func testKeepSessionActiveIsHiddenUntilAllowed() {
        // Turned off explicitly: the app reads the real user defaults of this Mac.
        let app = launch(arguments: ["-AllowKeepSessionActive", "NO"])
        openNewConnection(app)
        app.buttons["profile.advanced"].click()
        XCTAssertTrue(app.popUpButtons["profile.windowsSignIn"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["profile.keepSessionActive"].exists)
    }

    func testKeepSessionActiveIsSavedWhenAllowed() {
        let app = launch(arguments: ["-AllowKeepSessionActive", "YES"])
        openNewConnection(app)
        app.buttons["profile.advanced"].click()
        let keep = app.switches["profile.keepSessionActive"]
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        XCTAssertEqual(keep.value as? Int, 0)
        scrollIntoView(app, keep)
        keep.click()
        addConnection(app, name: "Office", computer: "pc01.example.com")

        app.buttons["connection.edit"].click()
        XCTAssertTrue(keep.waitForExistence(timeout: 5))
        XCTAssertEqual(keep.value as? Int, 1)
    }
}
