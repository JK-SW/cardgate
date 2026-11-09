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

    public init(
        executable: URL, profile: ConnectionProfile, pkcs11Module: String, config: FreeRDPClientConfig
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
        args.append("/log-level:INFO")
        return args
    }
}
