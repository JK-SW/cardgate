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

    /// - Parameter askPass: program FreeRDP runs to ask for the PIN (it prints the PIN to stdout).
    ///   `nil` keeps FreeRDP's own dialog.
    public init(
        executable: URL, profile: ConnectionProfile, pkcs11Module: String, config: FreeRDPClientConfig,
        askPass: AskPassCommand? = nil
    ) throws(BuildError) {
        guard pkcs11Module.hasPrefix("/"), !pkcs11Module.contains(","), !pkcs11Module.contains("\n") else {
            throw .invalidModulePath
        }
        self.executable = executable
        self.arguments = Self.arguments(profile: profile, pkcs11Module: pkcs11Module)
        self.environment = [
            // Smart card authentication to the RD Gateway (patched FreeRDP).
            "FREERDP_RDG_SMARTCARD": "1",
            "XDG_CONFIG_HOME": config.directory.path(percentEncoded: false),
        ]
        if let askPass {
            environment["FREERDP_ASKPASS"] = askPass.shellCommand
        }
    }

    static func arguments(profile: ConnectionProfile, pkcs11Module: String) -> [String] {
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
            // TODO: verify the gateway certificate properly instead of trust on first use.
            "/cert:tofu",
        ]

        switch profile.display.mode {
        case .window:
            args.append("/dynamic-resolution")
            if let size = profile.display.windowSize, size.isValid {
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
