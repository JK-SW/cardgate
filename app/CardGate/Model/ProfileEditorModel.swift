import CardGateKit
import Foundation
import Observation

/// Editable text form of a profile with validation.
@MainActor
@Observable
final class ProfileEditorModel: Identifiable {
    let id: UUID
    let isNew: Bool

    var name: String
    var computer: String
    var gateway: String
    var displayMode: DisplaySettings.Mode
    /// `nil` = automatic size.
    var windowSize: WindowSize?
    var clipboard: Bool
    var audio: Bool
    var scrollLikeThisMac: Bool
    var pkcs11Module: String

    init(profile: ConnectionProfile?, defaultName: String, isNew: Bool? = nil) {
        id = profile?.id ?? UUID()
        self.isNew = isNew ?? (profile == nil)
        name = profile?.name ?? defaultName
        computer = profile?.computer.description ?? ""
        gateway = profile?.gateway?.description ?? ""
        displayMode = profile?.display.mode ?? .window
        windowSize = profile?.display.windowSize
        clipboard = profile?.redirection.clipboard ?? true
        audio = profile?.redirection.audio ?? true
        scrollLikeThisMac = profile?.input.scrollLikeThisMac ?? true
        pkcs11Module = profile?.pkcs11Module ?? ""
    }

    /// Editor for a profile read from an `.rdp` file: new, but pre-filled.
    convenience init(importing profile: ConnectionProfile) {
        self.init(profile: profile, defaultName: profile.name, isNew: true)
    }

    var nameIsValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var computerError: HostAddress.ParseError? {
        Self.validate(computer, optional: false)
    }

    var gatewayError: HostAddress.ParseError? {
        Self.validate(gateway, optional: true)
    }

    var moduleIsValid: Bool {
        let path = pkcs11Module.trimmingCharacters(in: .whitespaces)
        return path.isEmpty || (path.hasPrefix("/") && !path.contains(","))
    }

    var canSave: Bool { nameIsValid && computerError == nil && gatewayError == nil && moduleIsValid }

    /// The edited profile, or `nil` while the input is invalid.
    func makeProfile() -> ConnectionProfile? {
        guard canSave, let computer = try? HostAddress(parsing: computer) else { return nil }
        let gatewayText = gateway.trimmingCharacters(in: .whitespaces)
        let module = pkcs11Module.trimmingCharacters(in: .whitespaces)
        return ConnectionProfile(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            computer: computer,
            gateway: gatewayText.isEmpty ? nil : try? HostAddress(parsing: gatewayText),
            pkcs11Module: module.isEmpty ? nil : module,
            display: .init(mode: displayMode, windowSize: displayMode == .window ? windowSize : nil),
            redirection: .init(clipboard: clipboard, audio: audio),
            input: .init(scrollLikeThisMac: scrollLikeThisMac))
    }

    private static func validate(_ text: String, optional: Bool) -> HostAddress.ParseError? {
        if optional && text.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        do {
            _ = try HostAddress(parsing: text)
            return nil
        } catch {
            return error
        }
    }
}
