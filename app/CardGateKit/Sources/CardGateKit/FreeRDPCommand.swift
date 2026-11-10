public import Foundation

/// Builds the command line and environment for the bundled `sdl-freerdp` client.
///
/// Secrets (the PIN) are never part of the command line; the client asks for them itself.
public struct FreeRDPCommand: Equatable, Sendable {
    public var executable: URL
    public var arguments: [String]
    public var environment: [String: String]

    public enum BuildError: Error, Equatable, Sendable {
        /// The PKCS#11 module path cannot be passed safely as a FreeRDP sub-option.
        case invalidModulePath
    }

    /// - Parameters:
    ///   - askPass: program FreeRDP runs to ask for the PIN (it prints the PIN to stdout).
    ///     `nil` keeps FreeRDP's own dialog.
    ///   - screen: the display the window opens on; window sizes are given in its points.
    ///   - certificateSHA1: card certificate to sign in with (when the card holds several).
    public init(
        executable: URL, profile: ConnectionProfile, pkcs11Module: String, config: FreeRDPClientConfig,
        askPass: AskPassCommand? = nil, screen: ScreenMetrics? = nil, certificateSHA1: String? = nil
    ) throws(BuildError) {
        guard pkcs11Module.hasPrefix("/"), !pkcs11Module.contains(","), !pkcs11Module.contains("\n") else {
            throw .invalidModulePath
        }
        self.executable = executable
        self.arguments = Self.arguments(profile: profile, pkcs11Module: pkcs11Module, screen: screen)
        self.environment = [
            // Smart card authentication to the RD Gateway (patched FreeRDP).
            "FREERDP_RDG_SMARTCARD": "1",
            "XDG_CONFIG_HOME": config.directory.path(percentEncoded: false),
        ]
        if let askPass {
            environment["FREERDP_ASKPASS"] = askPass.shellCommand
        }
        // Certificate chosen by CardGate when the card holds several (patched FreeRDP).
        if let certificateSHA1, CardCertificate.isFingerprint(certificateSHA1) {
            environment["FREERDP_SMARTCARD_CERT_SHA1"] = certificateSHA1.lowercased()
        }
    }

    static func arguments(profile: ConnectionProfile, pkcs11Module: String, screen: ScreenMetrics?) -> [String] {
        var args = ["/v:\(profile.computer)"]
        if let gateway = profile.gateway {
            args.append("/gateway:g:\(gateway),type:http,usage-method:direct")
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

        switch profile.display.mode {
        case .window:
            args.append("/dynamic-resolution")
            // FreeRDP takes the window size in pixels; the user chose it in points (what they see).
            let points = profile.display.windowSize ?? screen?.defaultWindowSize
            if let points, let size = screen?.pixels(for: points) ?? Optional(points), size.isValid {
                args.append("/size:\(size.width)x\(size.height)")
            }
        case .fullScreen:
            args.append("/f")
        case .allDisplays:
            args += ["/f", "/multimon"]
        }

        args.append(profile.redirection.clipboard ? "+clipboard" : "-clipboard")
        if profile.redirection.audio {
            args.append("/sound:sys:mac")
        }
        // CardGate shows progress and errors itself; no FreeRDP connection dialog.
        args.append("-sdl-connection-dialog")
        args.append("/log-level:INFO")
        // Display layout changes, for diagnosing window size issues.
        args.append("/log-filters:com.freerdp.client.sdl.disp:DEBUG")
        return args
    }
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
