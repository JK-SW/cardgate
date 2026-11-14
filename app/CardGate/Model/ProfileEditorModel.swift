import CardGateKit
import Foundation
import Observation

/// Editable text form of a profile with validation.
@MainActor
@Observable
final class ProfileEditorModel: Identifiable {
    let id: UUID
    let isNew: Bool
    /// Pre-filled from an `.rdp` file: the user is warned to check where it connects to.
    let isImported: Bool

    var name: String
    var computer: String
    var gateway: String
    var displayMode: DisplaySettings.Mode
    /// `nil` = automatic size.
    var windowSize: WindowSize?
    /// `nil` = follows the display.
    var scale: Int?
    var clipboard: Bool
    var audio: Bool
    var scrollLikeThisMac: Bool
    var pkcs11Module: String
    /// `nil` = automatic (newest valid certificate on the card).
    var certificateSHA1: String?

    init(profile: ConnectionProfile?, defaultName: String, isNew: Bool? = nil, isImported: Bool = false) {
        id = profile?.id ?? UUID()
        self.isNew = isNew ?? (profile == nil)
        self.isImported = isImported
        name = profile?.name ?? defaultName
        computer = profile?.computer.description ?? ""
        gateway = profile?.gateway?.description ?? ""
        displayMode = profile?.display.mode ?? DisplaySettings().mode
        windowSize = profile?.display.windowSize
        scale = profile?.display.validScale  // an invalid stored value means Automatic
        clipboard = profile?.redirection.clipboard ?? true
        audio = profile?.redirection.audio ?? true
        scrollLikeThisMac = profile?.input.scrollLikeThisMac ?? true
        pkcs11Module = profile?.pkcs11Module ?? ""
        certificateSHA1 = profile?.certificateSHA1
    }

    /// Editor for a profile read from an `.rdp` file: new, but pre-filled.
    convenience init(importing profile: ConnectionProfile) {
        self.init(profile: profile, defaultName: profile.name, isNew: true, isImported: true)
    }

    var nameIsValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var computerError: HostAddress.ParseError? {
        Self.validate(computer)
    }

    /// CardGate connects only through an RD Gateway (see `FreeRDPCommand.BuildError.gatewayRequired`).
    var gatewayError: HostAddress.ParseError? {
        Self.validate(gateway)
    }

    var moduleIsValid: Bool {
        let path = pkcs11Module.trimmingCharacters(in: .whitespaces)
        return path.isEmpty || FreeRDPCommand.isUsableModulePath(path)
    }

    var canSave: Bool { nameIsValid && computerError == nil && gatewayError == nil && moduleIsValid }

    /// The edited profile, or `nil` while the input is invalid.
    func makeProfile() -> ConnectionProfile? {
        guard canSave, let computer = try? HostAddress(parsing: computer) else { return nil }
        guard let gateway = try? HostAddress(parsing: gateway) else { return nil }
        let module = pkcs11Module.trimmingCharacters(in: .whitespaces)
        return ConnectionProfile(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            computer: computer,
            gateway: gateway,
            pkcs11Module: module.isEmpty ? nil : module,
            certificateSHA1: certificateSHA1,
            display: .init(
                mode: displayMode, windowSize: displayMode == .window ? windowSize : nil, scale: scale),
            redirection: .init(clipboard: clipboard, audio: audio),
            input: .init(scrollLikeThisMac: scrollLikeThisMac))
    }

    private static func validate(_ text: String) -> HostAddress.ParseError? {
        do {
            _ = try HostAddress(parsing: text)
            return nil
        } catch {
            return error
        }
    }
}
