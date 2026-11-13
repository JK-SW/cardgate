import XCTest

/// The card module of a connection: missing, or from an unverified publisher.
extension CardGateUITests {
    /// A configured module that does not exist: the connection's setting is named (not "install the
    /// card software"), Connect stays off (no card needed).
    func testAMissingModuleBlocksConnecting() {
        let app = launch()
        openNewConnection(app)
        addConnection(app, name: "Office", computer: "pc01.example.com", module: "/nonexistent/pkcs11.dylib")
        XCTAssertTrue(
            app.staticTexts["The smart card module set for this connection was not found."].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["/nonexistent/pkcs11.dylib"].exists)
        XCTAssertFalse(app.staticTexts["No smart card software found"].exists)
        XCTAssertFalse(app.buttons["connect"].isEnabled)
    }

    /// A module without a Developer ID signature is loaded only after the user confirms it. The test
    /// cancels the question, so it never stores an approval in the user's settings.
    func testAModuleFromAnUnverifiedPublisherNeedsApproval() throws {
        let module = try writeFile("unsigned.dylib", "not a signed library")
        let app = launch()
        openNewConnection(app)
        addConnection(app, name: "Office", computer: "pc01.example.com", module: module.path(percentEncoded: false))
        XCTAssertTrue(
            app.staticTexts["The smart card module is not from a verified publisher."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["connect"].isEnabled)

        app.buttons["module.approve"].click()
        // The alert may be a sheet or a dialog; its buttons are found either way.
        XCTAssertTrue(app.buttons["Use Module"].waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])  // Cancel of the alert, not another Cancel button
        XCTAssertTrue(app.buttons["module.approve"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["connect"].isEnabled)
    }
}
