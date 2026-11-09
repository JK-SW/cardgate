import CardGateKit
import Foundation
import Testing

struct FreeRDPCommandTests {
    let client = URL(filePath: "/Applications/CardGate.app/Contents/Helpers/sdl-freerdp")
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
                "/gateway:g:rdg.example.com,type:http,usage-method:direct",
                "/smartcard-logon",
                "/kerberos:pkcs11-module:\(module)",
                "/sec:rdp",
                "/cert:tofu",
                "/dynamic-resolution",
                "+clipboard",
                "/sound:sys:mac",
                "-sdl-connection-dialog",
                "/log-level:INFO",
                "/log-filters:com.freerdp.client.sdl.disp:DEBUG",
            ])
        #expect(
            command.environment == [
                "FREERDP_RDG_SMARTCARD": "1",
                "XDG_CONFIG_HOME": "/Users/test/Library/Application Support/CardGate/FreeRDP",
            ])
    }

    @Test func omitsGatewayForDirectConnections() throws {
        let args = try command(profile(gateway: nil)).arguments
        #expect(!args.contains { $0.hasPrefix("/gateway") })
    }

    @Test func keepsGatewayPort() throws {
        let args = try command(profile(gateway: "rdg.example.com:8443")).arguments
        #expect(args.contains("/gateway:g:rdg.example.com:8443,type:http,usage-method:direct"))
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
        #expect(!full.contains("/multimon"))
        #expect(!full.contains("/dynamic-resolution"))

        let all = try command(profile(display: .init(mode: .allDisplays))).arguments
        #expect(all.contains("/f"))
        #expect(all.contains("/multimon"))
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
