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
        XCTAssertTrue(app.staticTexts["rdg.example.com"].exists)
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

    /// Two connections: both are listed in the sidebar, each with its own Edit button, and picking
    /// one shows it in the detail.
    func testSeveralConnectionsAreListedInTheSidebar() {
        let app = launch()
        XCTAssertTrue(app.buttons["Set Up Connection"].waitForExistence(timeout: 10))
        app.buttons["Set Up Connection"].click()
        addConnection(app, name: "Office", computer: "pc01.example.com")
        app.typeKey("n", modifierFlags: .command)
        addConnection(app, name: "A connection with a rather long name", computer: "pc02.example.com")

        let computer = app.staticTexts["detail.computer"]
        // The new connection is selected once the editor has closed.
        let second = NSPredicate(format: "value == 'pc02.example.com'")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: second, evaluatedWith: computer)], timeout: 5), .completed)
        XCTAssertEqual(app.buttons.matching(identifier: "connection.edit").count, 2)
        XCTAssertTrue(app.buttons["toolbar.log"].isHittable)
        XCTAssertTrue(app.buttons["toolbar.shortcuts"].isHittable)

        app.outlines.staticTexts["Office"].click()
        let first = NSPredicate(format: "value == 'pc01.example.com'")
        XCTAssertEqual(XCTWaiter.wait(for: [expectation(for: first, evaluatedWith: computer)], timeout: 5), .completed)

        // A hidden sidebar comes back with the button in the toolbar.
        let showSidebar = app.buttons["toolbar.showSidebar"]
        XCTAssertFalse(showSidebar.exists)
        app.typeKey("s", modifierFlags: [.control, .command])  // View › Hide Sidebar
        XCTAssertTrue(showSidebar.waitForExistence(timeout: 5))
        showSidebar.click()
        XCTAssertTrue(app.buttons["sidebar.new"].waitForExistence(timeout: 5))
        XCTAssertFalse(showSidebar.exists)
    }

    func testEditsAndDeletesAConnection() {
        let app = launch()
        XCTAssertTrue(app.buttons["Set Up Connection"].waitForExistence(timeout: 10))
        app.buttons["Set Up Connection"].click()
        addConnection(app, name: "Office", computer: "pc01.example.com")

        app.buttons["connection.edit"].click()
        let name = app.textFields["profile.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click()
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Home Office")
        app.buttons["Save"].click()
        XCTAssertTrue(app.staticTexts["Home Office"].waitForExistence(timeout: 5))

        app.buttons["connection.edit"].click()
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
        // Not clicked either: they are stored in the user's real preferences.
        for option in ["settings.keepConnection", "settings.preventSleep", "settings.confirmDisconnect"] {
            XCTAssertTrue(app.switches[option].exists, option)
        }
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
        // The important messages in words, or every detail.
        XCTAssertTrue(app.windows["Connection Log"].descendants(matching: .any)["log.view"].exists)
        app.typeKey("w", modifierFlags: .command)

        choose(app, menu: "CardGate", item: "About CardGate")
        let about = app.windows["About CardGate"]
        XCTAssertTrue(about.links["Source Code"].waitForExistence(timeout: 5))
        XCTAssertTrue(about.links["Support the Author"].exists)
        XCTAssertTrue(about.links["Component Licenses"].exists)
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

        // Closing the advanced settings keeps the reason why saving is blocked in view.
        app.buttons["profile.advanced"].click()
        XCTAssertFalse(app.textFields["profile.module"].waitForExistence(timeout: 2))
        XCTAssertTrue(hint.exists)
    }

    func testCancelKeepsTheConnectionUnchanged() {
        let app = launch()
        openNewConnection(app)
        addConnection(app, name: "Office", computer: "pc01.example.com")
        app.buttons["connection.edit"].click()
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
        let cardReady = app.staticTexts["overview.cardReady"]
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
        XCTAssertTrue(app.staticTexts["rdg.example.com"].waitForExistence(timeout: 5))
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

        for button in ["sidebar.new", "sidebar.import", "toolbar.log", "toolbar.shortcuts"] {
            XCTAssertTrue(app.buttons[button].isHittable, button)
        }
        app.buttons["toolbar.log"].click()
        XCTAssertTrue(app.windows["Connection Log"].waitForExistence(timeout: 5))
        app.typeKey("w", modifierFlags: .command)
        app.buttons["toolbar.shortcuts"].click()
        XCTAssertTrue(app.windows["Keyboard Shortcuts"].waitForExistence(timeout: 5))
    }

    /// Without a connection nothing needs confirming: the app quits right away.
    func testQuitsWithoutAskingWhenNotConnected() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["Welcome to CardGate"].waitForExistence(timeout: 10))
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    }
}
