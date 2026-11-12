import CardGateKit
import Foundation
import Testing

struct FreeRDPCommandTests {
    let client = URL(filePath: "/Applications/CardGate.app/Contents")
        .appending(path: FreeRDPCommand.bundledClientPath)
    let module = "/usr/local/lib/middleware/pkcs11.dylib"
    let config = FreeRDPClientConfig(
        directory: URL(filePath: "/Users/test/Library/Application Support/CardGate/FreeRDP"))

    func profile(
        gateway: String? = "rdg.example.com",
        display: DisplaySettings = .init(),
        redirection: RedirectionSettings = .init()
    ) throws -> ConnectionProfile {
        ConnectionProfile(
            name: "Office",
            computer: try HostAddress(parsing: "pc01.corp.example"),
            gateway: try gateway.map { try HostAddress(parsing: $0) },
            display: display,
            redirection: redirection)
    }

    func command(_ profile: ConnectionProfile, module: String? = nil) throws -> FreeRDPCommand {
        try FreeRDPCommand(executable: client, profile: profile, pkcs11Module: module ?? self.module, config: config)
    }

    @Test func buildsGatewaySmartCardCommand() throws {
        let command = try command(profile())
        #expect(command.executable == client)
        #expect(
            command.arguments == [
                "/v:pc01.corp.example",
                "/title:Office – CardGate",
                "/gateway:g:rdg.example.com,type:http,usage-method:direct,auth:smartcard",
                "/smartcard-logon",
                "/kerberos:pkcs11-module:\(module)",
                "/sec:rdp",
                "/cert:deny",
                "/dynamic-resolution",
                "+clipboard",
                "/sound:sys:mac",
                "-sdl-connection-dialog",
                "/log-level:INFO",
                "/log-filters:com.freerdp.client.sdl.disp:DEBUG,com.freerdp.channels.disp.client:DEBUG,"
                    + "com.freerdp.utils.smartcard.ops:DEBUG,"
                    + "com.freerdp.utils.smartcard.call:TRACE",
            ])
        #expect(
            command.environment == [
                "XDG_CONFIG_HOME": "/Users/test/Library/Application Support/CardGate/FreeRDP",
                "SDL_MAC_BACKGROUND_APP": "1",
            ])
    }

    @Test func namesTheWindowAfterTheConnection() throws {
        var unnamed = try profile()
        unnamed.name = "  "
        #expect(try command(unnamed).arguments.contains("/title:pc01.corp.example – CardGate"))
    }

    @Test func redirectsOnlyTheReaderWithTheCard() throws {
        let command = try FreeRDPCommand(
            executable: client, profile: profile(), pkcs11Module: module, config: config,
            smartCardReader: "Example USB Reader")
        #expect(
            command.arguments.filter { $0.hasPrefix("/smartcard") } == [
                "/smartcard:Example USB Reader", "/smartcard-logon",
            ])

        for unusable in ["", "Reader, 2", "Reader\n2"] {
            let all = try FreeRDPCommand(
                executable: client, profile: profile(), pkcs11Module: module, config: config, smartCardReader: unusable)
            #expect(all.arguments.filter { $0.hasPrefix("/smartcard") } == ["/smartcard-logon"])
        }
    }

    /// The smart card data dumps contain the PIN the remote computer sends to the card.
    @Test func neverLogsSmartCardData() throws {
        let command = try FreeRDPCommand(executable: client, profile: profile(), pkcs11Module: module, config: config)
        let filters = try #require(command.arguments.first { $0.hasPrefix("/log-filters:") })
        #expect(!filters.contains("scard.pack"))
        #expect(!filters.contains("*"))
        #expect(command.arguments.contains("/log-level:INFO"))
    }

    @Test func omitsGatewayForDirectConnections() throws {
        let args = try command(profile(gateway: nil)).arguments
        #expect(!args.contains { $0.hasPrefix("/gateway") })
    }

    @Test func keepsGatewayPort() throws {
        let args = try command(profile(gateway: "rdg.example.com:8443")).arguments
        #expect(args.contains("/gateway:g:rdg.example.com:8443,type:http,usage-method:direct,auth:smartcard"))
    }

    @Test func windowWithInitialSize() throws {
        let display = DisplaySettings(mode: .window, windowSize: .init(width: 1920, height: 1080))
        let args = try command(profile(display: display)).arguments
        #expect(args.contains("/dynamic-resolution"))
        #expect(args.contains("/size:1920x1080"))
        #expect(!args.contains("/f"))
    }

    @Test func windowSizeIsConvertedToPixels() throws {
        let retina = ScreenMetrics(visibleSize: .init(width: 2560, height: 1415), scale: 2)
        let display = DisplaySettings(mode: .window, windowSize: .init(width: 1920, height: 1080))
        let args = try FreeRDPCommand(
            executable: client, profile: profile(display: display), pkcs11Module: module, config: config,
            screen: retina
        ).arguments
        #expect(args.contains("/size:3840x2160"))
    }

    @Test func automaticSizeIsEightyPercentOfTheScreen() throws {
        let retina = ScreenMetrics(visibleSize: .init(width: 2560, height: 1415), scale: 2)
        #expect(retina.defaultWindowSize == WindowSize(width: 2048, height: 1132))
        let args = try FreeRDPCommand(
            executable: client, profile: profile(), pkcs11Module: module, config: config, screen: retina
        ).arguments
        #expect(args.contains("/size:4096x2264"))
    }

    @Test func screenFit() {
        let screen = ScreenMetrics(visibleSize: .init(width: 1440, height: 875), scale: 2)
        #expect(screen.fits(.init(width: 1280, height: 800)))
        #expect(!screen.fits(.init(width: 1440, height: 900)))
        #expect(ScreenMetrics(visibleSize: .init(width: 100, height: 100), scale: 0).scale == 1)
    }

    @Test func ignoresInvalidWindowSize() throws {
        let display = DisplaySettings(mode: .window, windowSize: .init(width: 10, height: 10))
        let args = try command(profile(display: display)).arguments
        #expect(!args.contains { $0.hasPrefix("/size") })
    }

    @Test func fullScreenModes() throws {
        let full = try command(profile(display: .init(mode: .fullScreen))).arguments
        #expect(full.contains("/f"))
        #expect(!full.contains { $0.hasPrefix("/multimon") })

        let all = try command(profile(display: .init(mode: .allDisplays))).arguments
        #expect(all.contains("/f"))
        #expect(all.contains("/multimon:force"), "RDP security: the server never announces multi monitor support")
    }

    /// The remote desktop follows the scale of the display while connected (another display, full
    /// screen toggled) in every mode, not only in a window.
    @Test(arguments: DisplaySettings.Mode.allCases)
    func followsTheDisplayInEveryMode(_ mode: DisplaySettings.Mode) throws {
        let args = try command(profile(display: .init(mode: mode))).arguments
        #expect(args.contains("/dynamic-resolution"))
        #expect(!args.contains { $0.hasPrefix("/scale-desktop") })
    }

    @Test func chosenScale() throws {
        let args = try command(profile(display: .init(mode: .fullScreen, scale: 150))).arguments
        #expect(args.contains("/scale-desktop:150"))
    }

    @Test(arguments: [0, 99, 501])
    func ignoresInvalidScale(_ scale: Int) throws {
        #expect(DisplaySettings(scale: scale).validScale == nil)
        let args = try command(profile(display: .init(scale: scale))).arguments
        #expect(!args.contains { $0.hasPrefix("/scale-desktop") })
    }

    @Test(arguments: [100, 150, 500])
    func acceptsScalesOfRDP(_ scale: Int) {
        #expect(DisplaySettings(scale: scale).validScale == scale)
    }

    @Test func redirectionOff() throws {
        let args = try command(profile(redirection: .init(clipboard: false, audio: false))).arguments
        #expect(args.contains("-clipboard"))
        #expect(!args.contains { $0.hasPrefix("/sound") })
    }

    @Test(arguments: ["relative/module.dylib", "/path/with,comma.dylib", "/path/with\nnewline"])
    func rejectsUnsafeModulePaths(_ path: String) throws {
        let profile = try profile()
        #expect(throws: FreeRDPCommand.BuildError.invalidModulePath) {
            try command(profile, module: path)
        }
    }

    @Test func passesChosenCertificate() throws {
        let sha = String(repeating: "AB", count: 20)
        let command = try FreeRDPCommand(
            executable: client, profile: profile(), pkcs11Module: module, config: config, certificateSHA1: sha)
        #expect(command.environment["FREERDP_SMARTCARD_CERT_SHA1"] == sha.lowercased())
        let bad = try FreeRDPCommand(
            executable: client, profile: profile(), pkcs11Module: module, config: config, certificateSHA1: "x;rm")
        #expect(bad.environment["FREERDP_SMARTCARD_CERT_SHA1"] == nil)
    }

    @Test func neverContainsSecrets() throws {
        let args = try command(profile()).arguments
        #expect(!args.contains { $0.hasPrefix("/p:") || $0.hasPrefix("/gp:") || $0.contains("pin") })
    }
}

struct AskPassCommandTests {
    @Test func quotesForTheShell() {
        let command = AskPassCommand(
            executable: URL(filePath: "/Users/o'brien/Apps/Card Gate.app/Contents/MacOS/CardGate"),
            arguments: ["--askpass"])
        #expect(command.shellCommand == #"'/Users/o'\''brien/Apps/Card Gate.app/Contents/MacOS/CardGate' '--askpass'"#)
    }

    @Test func isPassedInTheEnvironment() throws {
        let askPass = AskPassCommand(
            executable: URL(filePath: "/Applications/CardGate.app/Contents/MacOS/CardGate"),
            arguments: ["--askpass"])
        let command = try FreeRDPCommand(
            executable: URL(filePath: "/x/sdl-freerdp"),
            profile: ConnectionProfile(name: "x", computer: HostAddress(parsing: "pc.example.com")),
            pkcs11Module: "/m.dylib", config: FreeRDPClientConfig(directory: URL(filePath: "/tmp/c")),
            askPass: askPass)
        #expect(command.environment["FREERDP_ASKPASS"] == askPass.shellCommand)
        #expect(!command.arguments.contains { $0.contains("askpass") })
    }

    @Test func extractsHostFromPrompt() {
        #expect(
            AskPassCommand.host(fromPrompt: "FreeRDP authentication\nCredentials required for rdg.example.com")
                == "rdg.example.com")
        #expect(AskPassCommand.host(fromPrompt: "FreeRDP authentication\nCredentials required for (null)") == nil)
        #expect(AskPassCommand.host(fromPrompt: "something else") == nil)
    }
}
