import AppKit
import CardGateKit
import Foundation
import OSLog
import Observation

/// State of the whole app: profiles, the profile being edited and the running session.
@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [ConnectionProfile] = []
    var selectedID: UUID? {
        didSet { if oldValue != selectedID { persist() } }
    }

    /// Profile shown in the editor sheet; `nil` when the sheet is closed.
    var editing: ProfileEditorModel?
    var isImportingRDP = false
    /// Error shown in an alert.
    var alert: AppAlert?

    let session = SessionController()
    let cards = CardMonitor()
    private(set) var middleware: PKCS11ModuleLocator.Middleware?

    private let store: ProfileStore?
    private let clientConfig: FreeRDPClientConfig?
    private let locator = PKCS11ModuleLocator()
    private let logger = Logger(subsystem: "io.github.jk-sw.cardgate", category: "app")

    init() {
        store = try? ProfileStore.standard()
        clientConfig = try? FreeRDPClientConfig.standard()
        load()
        refreshMiddleware()
        cards.onChange = { [weak self] in
            // A new card makes an old "no certificate" error irrelevant.
            self?.session.clearFinished()
        }
    }

    /// Everything needed to connect is in place.
    var isReadyToConnect: Bool {
        middleware != nil && cards.signInCertificate != nil && !session.isRunning && !cardNeedsReinsert
    }

    /// The system lists the card but the middleware's PKCS#11 module does not see it.
    var cardNeedsReinsert: Bool {
        switch cards.pkcs11State {
        case .noToken, .noCertificates: cards.signInCertificate != nil
        default: false
        }
    }

    var selectedProfile: ConnectionProfile? {
        profiles.first { $0.id == selectedID } ?? profiles.first
    }

    // MARK: - Profiles

    private func load() {
        guard let store else { return }
        do {
            let loaded = try store.load()
            profiles = loaded.profiles
            selectedID = loaded.selectedID ?? profiles.first?.id
        } catch {
            logger.error("Cannot load profiles: \(error.localizedDescription, privacy: .public)")
            alert = .profilesUnreadable
        }
    }

    private func persist() {
        guard let store else { return }
        do {
            try store.save(profiles: profiles, selectedID: selectedID)
        } catch {
            logger.error("Cannot save profiles: \(error.localizedDescription, privacy: .public)")
            alert = .profilesNotSaved
        }
    }

    func beginNewProfile() {
        editing = ProfileEditorModel(profile: nil, defaultName: String(localized: "My Computer"))
    }

    func beginEditing(_ profile: ConnectionProfile) {
        editing = ProfileEditorModel(profile: profile, defaultName: profile.name)
    }

    func save(_ profile: ConnectionProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        selectedID = profile.id
        editing = nil
        persist()
    }

    func delete(_ profile: ConnectionProfile) {
        profiles.removeAll { $0.id == profile.id }
        if selectedID == profile.id { selectedID = profiles.first?.id }
        editing = nil
        persist()
    }

    /// Opens the editor pre-filled from an `.rdp` file; the user confirms with Save.
    func importRDP(from url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let name = url.deletingPathExtension().lastPathComponent
            let profile = try RDPFile(contentsOf: url).makeProfile(name: name)
            editing = ProfileEditorModel(importing: profile)
        } catch {
            logger.error("Cannot import \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)")
            alert = .rdpUnreadable
        }
    }

    // MARK: - Middleware and connection

    func refreshMiddleware() {
        let module = locator.resolve(configured: selectedProfile?.pkcs11Module)
        middleware =
            locator.installed.first { $0.modulePath == module }
            ?? module.map { .init(name: URL(filePath: $0).lastPathComponent, modulePath: $0, downloadURL: nil) }
        cards.module = middleware?.modulePath
    }

    func connect() {
        guard let profile = selectedProfile else { return }
        refreshMiddleware()
        guard let module = middleware?.modulePath else {
            alert = .noMiddleware
            return
        }
        let executable = Bundle.main.bundleURL.appending(path: "Contents/Helpers/sdl-freerdp")
        guard let clientConfig, FileManager.default.isExecutableFile(atPath: executable.path(percentEncoded: false))
        else {
            alert = .clientMissing
            return
        }
        do {
            try clientConfig.install(for: profile)
            let command = try FreeRDPCommand(
                executable: executable, profile: profile, pkcs11Module: module,
                config: clientConfig, askPass: PINPrompt.command(module: module), screen: .current)
            try session.start(command)
        } catch {
            logger.error("Cannot start client: \(error, privacy: .public)")
            alert = .clientMissing
        }
    }
}

enum AppAlert: Identifiable {
    case profilesUnreadable
    case profilesNotSaved
    case rdpUnreadable
    case noMiddleware
    case clientMissing

    var id: Self { self }
}

extension ScreenMetrics {
    /// The display with the CardGate window (or the main display).
    @MainActor static var current: ScreenMetrics? {
        guard let screen = NSApp.keyWindow?.screen ?? NSScreen.main else { return nil }
        let frame = screen.visibleFrame
        return ScreenMetrics(
            visibleSize: .init(width: Int(frame.width), height: Int(frame.height)), scale: screen.backingScaleFactor)
    }
}
