public import Foundation

/// Builds the command line and environment for the bundled `sdl-freerdp` client.
///
/// Secrets (the PIN) are never part of the command line; the client asks for them itself.
public struct FreeRDPCommand: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]

    /// Where the client is in the app bundle (relative to `Contents`) and in the assembled helper
    /// (`build/helper`). It is wrapped in a small agent app (`LSUIElement`), so the Dock and the
    /// app switcher show only CardGate; CardGate brings the session window forward itself.
    public static let bundledClientPath = bundledClientApp + "/Contents/MacOS/sdl-freerdp"
    /// The agent app around the client, relative to `Contents` (its bundle identifier finds clients
    /// left running).
    public static let bundledClientApp = "Helpers/CardGateSession.app"

    /// The client's agent app inside the app bundle `app` (`CardGate.app`).
    public static func clientApp(in app: URL) -> URL {
        app.appending(path: "Contents").appending(path: bundledClientApp)
    }

    /// The client executable inside the app bundle `app`.
    public static func client(in app: URL) -> URL {
        app.appending(path: "Contents").appending(path: bundledClientPath)
    }

    public enum BuildError: Error, Equatable, Sendable {
        /// The PKCS#11 module path cannot be passed safely as a FreeRDP sub-option.
        case invalidModulePath
    }

    /// - Parameters:
    ///   - askPass: program FreeRDP runs to ask for the PIN (it prints the PIN to stdout).
    ///     `nil` keeps FreeRDP's own dialog.
    ///   - screen: the display the window opens on; window sizes are given in its points.
    ///   - certificateSHA1: card certificate to sign in with (when the card holds several).
    ///   - smartCardReader: the reader with the card; only it is redirected to the remote computer.
    public init(
        executable: URL, profile: ConnectionProfile, pkcs11Module: String, config: FreeRDPClientConfig,
        askPass: AskPassCommand? = nil, screen: ScreenMetrics? = nil, certificateSHA1: String? = nil,
        smartCardReader: String? = nil
    ) throws(BuildError) {
        guard pkcs11Module.hasPrefix("/"), !pkcs11Module.contains(","), !pkcs11Module.contains("\n") else {
            throw .invalidModulePath
        }
        self.executable = executable
        self.arguments = Self.arguments(profile: profile, pkcs11Module: pkcs11Module, screen: screen)
        if let reader = smartCardReader, Self.isUsableReaderFilter(reader) {
            // Without it every reader of the Mac is redirected; Windows sign-in then may look at an
            // empty one (e.g. a reader built into the keyboard) and ask to insert the card.
            let position = arguments.firstIndex(of: "/smartcard-logon") ?? arguments.endIndex
            arguments.insert("/smartcard:\(reader)", at: position)
        }
        self.environment = [
            "XDG_CONFIG_HOME": config.directory.path(percentEncoded: false),
            // SDL would otherwise make the client a regular app with its own Dock icon.
            "SDL_MAC_BACKGROUND_APP": "1",
        ]
        if let askPass {
            environment["FREERDP_ASKPASS"] = askPass.shellCommand
        }
        // Certificate chosen by CardGate when the card holds several (patched FreeRDP).
        if let certificateSHA1, CardCertificate.isFingerprint(certificateSHA1) {
            environment["FREERDP_SMARTCARD_CERT_SHA1"] = certificateSHA1.lowercased()
        }
    }

    /// Variables of the app's environment the client and the PIN dialog it starts still get.
    /// Nothing else is passed on: WinPR reads its log settings from the environment (`WLOG_FILTER`
    /// could turn on the smart card data dumps, which contain the PIN), OpenSSL its trust store
    /// (`SSL_CERT_FILE`) and dyld libraries to load (`DYLD_INSERT_LIBRARIES`). The proxy variables
    /// stay: FreeRDP connects to the gateway through them (`libfreerdp/core/proxy.c`).
    public static let inheritedVariables: Set<String> = [
        "HOME", "USER", "LOGNAME", "TMPDIR", "PATH", "SHELL", "LANG", "__CF_USER_TEXT_ENCODING",
        "https_proxy", "HTTPS_PROXY", "no_proxy", "NO_PROXY",
    ]

    /// The environment to start the client with: the allowed variables of `inherited` (and the
    /// locale, `LC_*`) and this command's own variables.
    public func processEnvironment(inheriting inherited: [String: String]) -> [String: String] {
        inherited
            .filter { Self.inheritedVariables.contains($0.key) || $0.key.hasPrefix("LC_") }
            .merging(environment) { _, own in own }
    }

    /// FreeRDP redirects readers whose name contains this text; it splits its options at commas.
    static func isUsableReaderFilter(_ reader: String) -> Bool {
        !reader.isEmpty && !reader.contains(",") && !reader.contains(where: \.isNewline)
    }

    static func arguments(profile: ConnectionProfile, pkcs11Module: String, screen: ScreenMetrics?) -> [String] {
        let name = profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        var args = [
            "/v:\(profile.computer)",
            // The window is named after the connection, not "FreeRDP: <address>".
            "/title:\(name.isEmpty ? profile.computer.description : name) – CardGate",
        ]
        if let gateway = profile.gateway {
            // auth:smartcard = smart card authentication to the RD Gateway (patched FreeRDP).
            args.append("/gateway:g:\(gateway),type:http,usage-method:direct,auth:smartcard")
        }
        args += [
            // Log on with the card redirected into the session; the PKCS#11 module provides the
            // certificate for the gateway. RDP security avoids a first TLS attempt the server rejects.
            "/smartcard-logon",
            "/kerberos:pkcs11-module:\(pkcs11Module)",
            "/sec:rdp",
            // The gateway certificate must be trusted by the system CAs; never ask the user.
            "/cert:deny",
        ]

        // The remote desktop follows the size and scale of the window or display while connected
        // (moved to another display, full screen toggled, displays added or removed). When
        // connecting the client sends the scale of the display it opens on (patch 0009).
        args.append("/dynamic-resolution")
        if let scale = profile.display.validScale {
            // Replaces the display's scale, when connecting and while connected.
            args.append("/scale-desktop:\(scale)")
        }
        switch profile.display.mode {
        case .window:
            // FreeRDP takes the window size in pixels; the user chose it in points (what they see).
            let points = profile.display.windowSize ?? screen?.defaultWindowSize
            if let points, let size = screen?.pixels(for: points) ?? Optional(points), size.isValid {
                args.append("/size:\(size.width)x\(size.height)")
            }
        case .fullScreen:
            args.append("/f")
        case .allDisplays:
            // RDP security negotiates nothing, so the server never announces that it takes the
            // displays when connecting; without force FreeRDP sends one rectangle around all of
            // them and parts of the remote desktop lie off screen.
            args += ["/f", "/multimon:force"]
        }

        args.append(profile.redirection.clipboard ? "+clipboard" : "-clipboard")
        if profile.redirection.audio {
            args.append("/sound:sys:mac")
        }
        // CardGate shows progress and errors itself; no FreeRDP connection dialog.
        args.append("-sdl-connection-dialog")
        args.append("/log-level:INFO")
        args.append("/log-filters:" + logFilters.joined(separator: ","))
        return args
    }

    /// Extra log detail for support. Only operation names and result codes: the smart card data
    /// channel (`com.freerdp.scard.pack`) is never raised, its dumps would contain the PIN sent to
    /// the card by the remote computer.
    static let logFilters = [
        // Display layout changes, for diagnosing window size issues.
        "com.freerdp.client.sdl.disp:DEBUG",
        // The layout and scale of each monitor sent to the remote computer while connected (the
        // scale sent when connecting is logged by the client itself, at INFO).
        "com.freerdp.channels.disp.client:DEBUG",
        // Smart card redirection: what the remote computer asks the card and what fails.
        "com.freerdp.utils.smartcard.ops:DEBUG",
        "com.freerdp.utils.smartcard.call:TRACE",
    ]
}

/// Program started by FreeRDP to ask for a secret: `<executable> <arguments…> '<prompt>'`.
public struct AskPassCommand: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]

    public init(executable: URL, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }

    /// FreeRDP runs `FREERDP_ASKPASS` through the shell (`popen`), so every word is quoted.
    public var shellCommand: String {
        ([executable.path(percentEncoded: false)] + arguments).map(Self.shellQuoted).joined(separator: " ")
    }

    static func shellQuoted(_ word: String) -> String {
        "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    /// Extracts what FreeRDP asks for from the prompt argument it passes
    /// (`"FreeRDP authentication\nCredentials required for <host>"`): the host name, if any.
    public static func host(fromPrompt prompt: String) -> String? {
        guard let range = prompt.range(of: "Credentials required for ") else { return nil }
        let host = prompt[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return host.isEmpty || host == "(null)" ? nil : host
    }
}

/// Size of the usable area of a display in points and its pixel density.
public struct ScreenMetrics: Equatable, Sendable {
    public var visibleSize: WindowSize
    /// Pixels per point (2 on Retina displays).
    public var scale: Double

    public init(visibleSize: WindowSize, scale: Double) {
        self.visibleSize = visibleSize
        self.scale = max(scale, 1)
    }

    /// Window size used when the user did not choose one: 80 % of the usable area.
    public var defaultWindowSize: WindowSize {
        WindowSize(width: visibleSize.width * 4 / 5, height: visibleSize.height * 4 / 5)
    }

    /// Whether a window of this size (in points) fits on the display.
    public func fits(_ size: WindowSize) -> Bool {
        size.width <= visibleSize.width && size.height <= visibleSize.height
    }

    func pixels(for size: WindowSize) -> WindowSize {
        WindowSize(
            width: Int((Double(size.width) * scale).rounded()), height: Int((Double(size.height) * scale).rounded()))
    }
}
