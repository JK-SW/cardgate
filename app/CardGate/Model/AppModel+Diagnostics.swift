import AppKit
import CardGateKit
@preconcurrency import CryptoTokenKit
import Network
import Security

/// The anonymous diagnostic information of the saved log (`DiagnosticReport`): what helps to find a
/// problem, without names, addresses, the card's holder or certificates.
extension AppModel {
    /// Hides the computer, the gateway and the connection's name of the last connection (the log
    /// shown is its log), else of the selected one.
    var logAnonymizer: LogAnonymizer {
        let profile = lastAttempt?.profile ?? selectedProfile
        return LogAnonymizer(
            computer: profile?.computer.host ?? "", gateway: profile?.gateway?.host, name: profile?.name ?? "")
    }

    func diagnosticReport(at date: Date = .now) -> DiagnosticReport {
        DiagnosticReport(sections: [
            appSection(at: date), Self.macSection(), Self.displaysSection(), cardSection(), connectionSection(),
            settingsSection(), .init("Updates", updateStatus?() ?? [("Updates", "?")]), lastConnectionSection(),
            networkSection(),
        ])
    }

    private func appSection(at date: Date) -> DiagnosticReport.Section {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return .init(
            "CardGate",
            [
                ("Version", "\(version) (build \(build))"),
                ("Language", Bundle.main.preferredLocalizations.first ?? "?"),
                ("Created", DiagnosticReport.time(date)),
            ])
    }

    private static func macSection() -> DiagnosticReport.Section {
        let memory = ProcessInfo.processInfo.physicalMemory / 1_073_741_824
        return .init(
            "Mac",
            [
                ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
                ("Model", sysctl("hw.model") ?? "?"),
                ("Chip", sysctl("machdep.cpu.brand_string") ?? "?"),
                ("Memory", "\(memory) GB"),
            ])
    }

    private static func displaysSection() -> DiagnosticReport.Section {
        let main = NSScreen.main
        let items = NSScreen.screens.enumerated().map { index, screen in
            let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            let size = screen.frame.size
            let scale = screen.backingScaleFactor
            var parts = [
                screen.localizedName,
                number.map { CGDisplayIsBuiltin($0) != 0 } == true ? "built-in" : "external",
                "\(Int(size.width))×\(Int(size.height)) points",
                "scale \(scale.formatted())",
                "\(Int(size.width * scale))×\(Int(size.height * scale)) pixels",
            ]
            if screen.safeAreaInsets.top > 0 { parts.append("notch") }
            if screen == main { parts.append("main") }
            return ("Display \(index + 1)", parts.joined(separator: ", "))
        }
        return .init("Displays", items.isEmpty ? [("Displays", "none")] : items)
    }

    private func cardSection() -> DiagnosticReport.Section {
        var items: [(String, String)] = [
            ("Readers", TKSmartCardSlotManager.default?.slotNames.sorted().joined(separator: "; ") ?? "?"),
            ("Reader with the card", cards.tokenReader ?? "-"),
            ("Card check", cards.pkcs11State.map(Self.describe) ?? "not checked"),
        ]
        if let middleware {
            items.append(("PKCS#11 module", DiagnosticReport.anonymizedPath(middleware.modulePath)))
            items.append(
                (
                    "Module signature",
                    Self.signature(
                        ofModuleAt: middleware.modulePath,
                        checked: checkedSignature(ofModuleAt: middleware.modulePath))
                ))
        } else {
            items.append(("PKCS#11 module", "not found"))
        }
        if let info = cards.moduleInfo {
            items.append(("Module", info.module.isEmpty ? "?" : info.module))
            if !info.token.isEmpty { items.append(("Card", info.token)) }
        }
        let certificates = cards.certificates
        items.append(("Certificates", "\(certificates.count) (\(certificates.filter(\.isLogon).count) for sign-in)"))
        if let certificate = signInCertificate {
            items.append(("Sign-in certificate", Self.describe(certificate)))
        }
        return .init("Smart card", items)
    }

    private func connectionSection() -> DiagnosticReport.Section {
        // The one of the last connection (its result is below), else the selected one.
        guard let profile = lastAttempt?.profile ?? selectedProfile else {
            return .init("Connection", [("Connection", "none")])
        }
        let display = profile.display
        var items: [(String, String)] = [
            ("Security", profile.security.rawValue),
            ("Remembered security", securityMemory.remembered(for: profile)?.method.rawValue ?? "-"),
            ("NLA failed recently", DiagnosticReport.yesNo(securityMemory.nlaRecentlyFailed(for: profile, at: .now))),
            ("Windows sign-in", profile.windowsSignIn.rawValue),
            ("Display", display.mode.rawValue),
            ("Window size", display.windowSize?.description ?? "-"),
            ("Scale", display.validScale.map { "\($0) %" } ?? "-"),
            ("Display chosen for full screen", DiagnosticReport.yesNo(display.fullScreenDisplay != nil)),
            ("Clipboard", DiagnosticReport.yesNo(profile.redirection.clipboard)),
            ("Sound", DiagnosticReport.yesNo(profile.redirection.audio)),
            ("Certificate chosen", DiagnosticReport.yesNo(profile.certificateSHA1 != nil)),
            ("Own PKCS#11 module", DiagnosticReport.yesNo(profile.pkcs11Module != nil)),
        ]
        if profile.keepSessionActive { items.append(("Keep session active", "yes")) }
        return .init("Connection", items)
    }

    private func settingsSection() -> DiagnosticReport.Section {
        let options = SessionOptions(defaults: .standard, question: Self.disconnectQuestion)
        return .init(
            "Settings",
            [
                ("Keep the connection", DiagnosticReport.yesNo(options.keepConnection)),
                ("Prevent sleep", DiagnosticReport.yesNo(options.preventSleep)),
                ("Confirm disconnect", DiagnosticReport.yesNo(options.disconnectQuestion != nil)),
            ])
    }

    private func lastConnectionSection() -> DiagnosticReport.Section {
        let result: String =
            switch session.phase {
            case nil: "none"
            case .ended(.closedByUser): "disconnected"
            case .ended(.failed(let failure)): "failed: \(failure)"
            case let phase?: "\(phase)"
            }
        return .init(
            "Last connection",
            [
                ("Result", result),
                ("Negotiated security", session.negotiatedSecurity?.rawValue ?? "-"),
                ("Gateway", gatewayStatus.map { "\($0)" } ?? "not checked"),
            ])
    }

    private func networkSection() -> DiagnosticReport.Section {
        let path = networkMonitor.currentPath
        let names: [(NWInterface.InterfaceType, String)] = [
            (.wifi, "Wi-Fi"), (.wiredEthernet, "wired"), (.cellular, "cellular"), (.other, "other (e.g. VPN)"),
        ]
        let types = names.filter { path.usesInterfaceType($0.0) }.map(\.1)
        return .init(
            "Network",
            [
                ("Status", "\(path.status)"),
                ("In use", types.isEmpty ? "-" : types.joined(separator: ", ")),
                (
                    "IPv4 / IPv6",
                    "\(DiagnosticReport.yesNo(path.supportsIPv4)) / \(DiagnosticReport.yesNo(path.supportsIPv6))"
                ),
            ])
    }

    // MARK: - Helpers

    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return String(bytes: value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, encoding: .utf8)
    }

    private static func describe(_ state: PKCS11CardState) -> String {
        switch state {
        case .ready: "card ready"
        case .noToken: "no card"
        case .moduleNotLoadable: "module cannot be loaded"
        case .failed(let code): "failed (\(code))"
        }
    }

    /// Key type and size, sign-in use and validity; never the holder or the fingerprint.
    private static func describe(_ certificate: CardCertificate) -> String {
        var parts: [String] = []
        if let der = certificate.der, let parsed = SecCertificateCreateWithData(nil, der as CFData),
            let key = SecCertificateCopyKey(parsed),
            let attributes = SecKeyCopyAttributes(key) as? [CFString: Any]
        {
            let type = attributes[kSecAttrKeyType] as? String
            let name =
                type == (kSecAttrKeyTypeRSA as String)
                ? "RSA" : type == (kSecAttrKeyTypeECSECPrimeRandom as String) ? "EC" : "other key"
            parts.append(
                [name, (attributes[kSecAttrKeySizeInBits] as? Int).map(String.init)].compactMap(\.self).joined(
                    separator: " "))
        }
        parts.append(certificate.isLogon ? "smart card logon" : "no smart card logon use")
        if let notAfter = certificate.notAfter {
            let day = notAfter.formatted(.iso8601.year().month().day())
            parts.append(notAfter < .now ? "expired \(day)" : "valid until \(day)")
        }
        return parts.joined(separator: ", ")
    }

    /// "Developer ID: Example Corp (TEAMID)": the result of the check before loading (not checked
    /// again: it reads the whole file) and the signer's name, read without validating.
    private static func signature(ofModuleAt path: String, checked: ModuleSignature?) -> String {
        let kind: String =
            switch checked {
            case .developerID: "Developer ID"
            case .unverified: "signed, not by a verified developer"
            case .unsigned: "unsigned"
            case .invalid: "invalid signature"
            case nil: "not checked"
            }
        var code: SecStaticCode?
        var information: CFDictionary?
        guard SecStaticCodeCreateWithPath(URL(filePath: path) as CFURL, [], &code) == errSecSuccess, let code,
            SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
                == errSecSuccess,
            let certificates = (information as? [String: Any])?[kSecCodeInfoCertificates as String]
                as? [SecCertificate],
            let leaf = certificates.first,
            let summary = SecCertificateCopySubjectSummary(leaf) as String?
        else { return kind }
        return "\(kind): \(summary)"
    }
}
