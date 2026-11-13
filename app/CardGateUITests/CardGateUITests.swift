import XCTest

/// Drives the app like a user. Every test starts the app with an empty data directory
/// (`CARDGATE_DATA_DIR`), so the user's connections are never touched, and in English unless the
/// test asks for another language. Nothing here needs a smart card.
@MainActor
final class CardGateUITests: XCTestCase {
    var dataDirectory: URL?

    override func setUp() async throws {
        continueAfterFailure = false
        let directory = FileManager.default.temporaryDirectory.appending(path: "CardGateUITests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        dataDirectory = directory
    }

    override func tearDown() async throws {
        XCUIApplication().terminate()
        if let dataDirectory { try? FileManager.default.removeItem(at: dataDirectory) }
    }

    func testFirstLaunchSetsUpAConnection() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Welcome to CardGate"].waitForExistence(timeout: 10))
        app.buttons["Set Up Connection"].click()
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Save needs the computer address")

        addConnection(app, name: "Office", computer: "pc01.example.com", gateway: "rdg.example.com")
        XCTAssertTrue(app.staticTexts["pc01.example.com"].exists)
        XCTAssertTrue(app.staticTexts["via rdg.example.com"].exists)
        XCTAssertFalse(app.staticTexts["Welcome to CardGate"].exists)
    }

    func testRejectsAnInvalidAddress() {
        let app = launch()
        XCTAssertTrue(app.buttons["Set Up Connection"].waitForExistence(timeout: 10))
        app.buttons["Set Up Connection"].click()
        let computer = app.textFields["profile.computer"]
        XCTAssertTrue(computer.waitForExistence(timeout: 5))
        computer.click()
        computer.typeText("not a valid address")
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        app.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["Welcome to CardGate"].waitForExistence(timeout: 5))
    }

    /// Two connections: the picker replaces the title and both toolbar buttons stay visible
    /// (they once moved into an overflow menu).
    func testSeveralConnectionsKeepTheToolbarUsable() {
        let app = launch()
        XCTAssertTrue(app.buttons["Set Up Connection"].waitForExistence(timeout: 10))
        app.buttons["Set Up Connection"].click()
        addConnection(app, name: "Office", computer: "pc01.example.com")
        app.typeKey("n", modifierFlags: .command)
        addConnection(app, name: "A connection with a rather long name", computer: "pc02.example.com")

        let picker = app.popUpButtons["Connection"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["toolbar.edit"].isHittable)
        XCTAssertTrue(app.menuButtons["toolbar.more"].isHittable)

        picker.click()
        app.menuItems["Office"].click()
        XCTAssertTrue(app.staticTexts["pc01.example.com"].waitForExistence(timeout: 5))
    }

    func testEditsAndDeletesAConnection() {
        let app = launch()
        XCTAssertTrue(app.buttons["Set Up Connection"].waitForExistence(timeout: 10))
        app.buttons["Set Up Connection"].click()
        addConnection(app, name: "Office", computer: "pc01.example.com")

        app.buttons["toolbar.edit"].click()
        let name = app.textFields["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Home Office")
        app.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts["Home Office"].waitForExistence(timeout: 5))

        app.buttons["toolbar.edit"].click()
        XCTAssertTrue(app.buttons["Delete Connection…"].waitForExistence(timeout: 5))
        app.buttons["Delete Connection…"].click()
        // Only in the app's windows: CI runners also show the button on a virtual Touch Bar.
        app.windows.buttons["Delete"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Welcome to CardGate"].waitForExistence(timeout: 5))
    }

    func testConnectionsSurviveARestart() {
        var app = launch()
        XCTAssertTrue(app.buttons["Set Up Connection"].waitForExistence(timeout: 10))
        app.buttons["Set Up Connection"].click()
        addConnection(app, name: "Office", computer: "pc01.example.com")
        app.terminate()

        app = launch()
        XCTAssertTrue(app.staticTexts["Office"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["pc01.example.com"].exists)
    }

    func testOpensTheAppWindows() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Welcome to CardGate"].waitForExistence(timeout: 10))

        app.typeKey(",", modifierFlags: .command)
        // Not clicked: Sparkle would store the choice in the user's real preferences.
        let automaticUpdates = app.switches["settings.automaticUpdates"]
        XCTAssertTrue(automaticUpdates.waitForExistence(timeout: 5))
        XCTAssertEqual(automaticUpdates.value as? Int, 0, "-SUEnableAutomaticChecks NO is shown")
        XCTAssertTrue(app.staticTexts["Check for updates automatically"].exists)
        app.typeKey("w", modifierFlags: .command)

        // The guide opens in the browser; only its presence is checked.
        let help = app.menuBars.menuBarItems["Help"]
        help.click()
        XCTAssertTrue(help.menuItems["CardGate User Guide"].exists)
        help.menuItems["Keyboard Shortcuts"].click()
        XCTAssertTrue(app.windows["Keyboard Shortcuts"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)

        app.typeKey("l", modifierFlags: [.command, .option])
        XCTAssertTrue(app.windows["Connection Log"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)

        choose(app, menu: "CardGate", item: "About CardGate")
        let about = app.windows["About CardGate"]
        XCTAssertTrue(about.links["Source Code"].waitForExistence(timeout: 5))
        XCTAssertTrue(about.links["Support the Author"].exists)
        XCTAssertTrue(about.links["Third-Party Licenses"].exists)
        XCTAssertTrue(about.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Version '")).firstMatch.exists)
    }

    func testSpeaksCzech() {
        let app = launch(language: "cs")
        XCTAssertTrue(app.staticTexts["Vítejte v CardGate"].waitForExistence(timeout: 10))
        app.buttons["Nastavit připojení"].click()
        XCTAssertTrue(app.textFields["profile.computer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Uložit"].exists)
    }

    func testSpeaksSlovak() {
        let app = launch(language: "sk")
        XCTAssertTrue(app.staticTexts["Vitajte v CardGate"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Nastaviť pripojenie"].exists)
    }

    func testWindowSizeIsOnlyOfferedForAWindow() {
        let app = launch()
        openNewConnection(app)
        XCTAssertTrue(app.popUpButtons["profile.windowSize"].exists)
        app.popUpButtons["profile.displayMode"].click()
        app.menuItems["Full screen"].click()
        XCTAssertFalse(app.popUpButtons["profile.windowSize"].exists)
        app.popUpButtons["profile.displayMode"].click()
        app.menuItems["Window"].click()
        XCTAssertTrue(app.popUpButtons["profile.windowSize"].waitForExistence(timeout: 5))
    }

    /// The scale is offered in every display mode and saved.
    func testScaleIsSaved() {
        let app = launch()
        openNewConnection(app)
        let scale = app.popUpButtons["profile.scale"]
        XCTAssertEqual(scale.value as? String, "Automatic")
        app.popUpButtons["profile.displayMode"].click()
        app.menuItems["Full screen"].click()
        scale.click()
        // The percent format depends on the region ("150%" or "150 %").
        app.menuItems.matching(NSPredicate(format: "title BEGINSWITH '150'")).firstMatch.click()
        addConnection(app, name: "Office", computer: "pc01.example.com")

        app.buttons["toolbar.edit"].click()
        XCTAssertTrue(scale.waitForExistence(timeout: 5))
        XCTAssertTrue((scale.value as? String)?.hasPrefix("150") == true)
    }

    func testRejectsAnInvalidGatewayAndModule() {
        let app = launch()
        openNewConnection(app)
        app.textFields["profile.computer"].click()
        app.textFields["profile.computer"].typeText("pc01.example.com")
        XCTAssertFalse(app.buttons["Save"].isEnabled, "the gateway is required")
        XCTAssertTrue(app.staticTexts["Enter the address of the RD Gateway."].exists)

        app.textFields["profile.gateway"].click()
        app.textFields["profile.gateway"].typeText("not a gateway")
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        app.textFields["profile.gateway"].typeKey("a", modifierFlags: .command)
        app.textFields["profile.gateway"].typeText("rdg.example.com")
        XCTAssertTrue(app.buttons["Save"].isEnabled)

        typeModule(app, "relative/module.dylib")
        let hint = app.staticTexts["Enter the full path of the module, starting with /, without commas."]
        XCTAssertTrue(hint.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
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

        app.buttons["toolbar.edit"].click()
        XCTAssertTrue(clipboard.waitForExistence(timeout: 5))
        XCTAssertEqual(clipboard.value as? Int, 0)
        XCTAssertEqual(audio.value as? Int, 0)
    }

    func testCancelKeepsTheConnectionUnchanged() {
        let app = launch()
        openNewConnection(app)
        addConnection(app, name: "Office", computer: "pc01.example.com")
        app.buttons["toolbar.edit"].click()
        let computer = app.textFields["profile.computer"]
        XCTAssertTrue(computer.waitForExistence(timeout: 5))
        computer.click()
        computer.typeKey("a", modifierFlags: .command)
        computer.typeText("pc99.example.com")
        app.buttons["Cancel"].click()
        XCTAssertTrue(app.staticTexts["pc01.example.com"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["pc99.example.com"].exists)
    }

    /// Connect is only possible with a usable card; the test never clicks it (no PIN).
    func testConnectFollowsTheCardReadiness() {
        let app = launch()
        openNewConnection(app)
        addConnection(app, name: "Office", computer: "pc01.example.com")
        let connect = app.buttons["connect"]
        XCTAssertTrue(connect.waitForExistence(timeout: 5))
        // The card check runs in the background; give it time to settle.
        let cardReady = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Card ready: '")).firstMatch
        _ = cardReady.waitForExistence(timeout: 10)
        XCTAssertEqual(connect.isEnabled, cardReady.exists)
    }

    func testImportsAnRDPFile() throws {
        let file = try writeFile(
            "Branch Office.rdp",
            "full address:s:pc03.example.com\ngatewayhostname:s:rdg.example.com\ngatewayusagemethod:i:1\n"
                + "screen mode id:i:2\n")
        let app = launch()
        XCTAssertTrue(app.staticTexts["Welcome to CardGate"].waitForExistence(timeout: 10))
        importFile(app, file)
        let computer = app.textFields["profile.computer"]
        XCTAssertTrue(computer.waitForExistence(timeout: 10))
        XCTAssertEqual(computer.value as? String, "pc03.example.com")
        XCTAssertEqual(app.textFields["profile.gateway"].value as? String, "rdg.example.com")
        XCTAssertEqual(app.textFields["profile.name"].value as? String, "Branch Office")
        XCTAssertEqual(app.popUpButtons["profile.displayMode"].value as? String, "Full screen")
        app.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts["Branch Office"].waitForExistence(timeout: 5))
    }

    /// A file from anywhere (an e-mail attachment) can name any gateway: the editor warns, and a
    /// file without a gateway cannot be saved until one is added.
    func testImportWarnsAndRequiresAGateway() throws {
        let file = try writeFile("Direct.rdp", "full address:s:pc04.example.com\n")
        let app = launch()
        XCTAssertTrue(app.staticTexts["Welcome to CardGate"].waitForExistence(timeout: 10))
        importFile(app, file)
        XCTAssertTrue(app.textFields["profile.computer"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["profile.importWarning"].firstMatch.exists)
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        app.textFields["profile.gateway"].click()
        app.textFields["profile.gateway"].typeText("rdg.example.com")
        XCTAssertTrue(app.buttons["Save"].isEnabled)
    }

    /// Older versions saved connections without a gateway; the main window says so and offers to
    /// add one instead of connecting.
    func testConnectionWithoutGatewayAsksForOne() throws {
        _ = try writeFile(
            "profiles.json",
            #"{"version":1,"profiles":[{"id":"6F1C2A52-8B39-4B79-9A43-2B7D4D0B5E10","name":"Old","#
                + #""computer":"pc01.example.com","display":{"mode":"window"},"#
                + #""redirection":{"clipboard":true,"audio":true}}]}"#)
        let app = launch()
        XCTAssertTrue(app.staticTexts["The connection has no gateway"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["connect"].isEnabled)
        app.buttons["missingGateway.edit"].click()
        let gateway = app.textFields["profile.gateway"]
        XCTAssertTrue(gateway.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        gateway.click()
        gateway.typeText("rdg.example.com")
        app.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts["via rdg.example.com"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["The connection has no gateway"].exists)
    }

    func testReportsAnUnreadableRDPFile() throws {
        let file = try writeFile("Broken.rdp", "this is not a remote desktop file\n")
        let app = launch()
        XCTAssertTrue(app.staticTexts["Welcome to CardGate"].waitForExistence(timeout: 10))
        importFile(app, file)
        XCTAssertTrue(app.staticTexts["The file cannot be imported"].waitForExistence(timeout: 10))
    }

    func testMenusOfferTheConnectionCommands() {
        let app = launch()
        openNewConnection(app)
        addConnection(app, name: "Office", computer: "pc01.example.com")

        let file = app.menuBars.menuBarItems["File"]
        file.click()
        XCTAssertTrue(file.menuItems["New Connection…"].isEnabled)
        XCTAssertTrue(file.menuItems["Import .rdp File…"].isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        let more = app.menuButtons["toolbar.more"]
        more.click()
        for item in ["New Connection…", "Import .rdp File…", "Keyboard Shortcuts", "Connection Log"] {
            XCTAssertTrue(app.menuItems[item].firstMatch.exists, "More menu offers \(item)")
        }
        app.typeKey(.escape, modifierFlags: [])
    }

    /// Without a connection nothing needs confirming: the app quits right away.
    func testQuitsWithoutAskingWhenNotConnected() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Welcome to CardGate"].waitForExistence(timeout: 10))
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    }
}
