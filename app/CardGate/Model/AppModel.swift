import AppKit
import CardGateKit
import Foundation
import Network
import OSLog
import Observation
import Security

/// State of the whole app: profiles, the profile being edited and the running session.
@MainActor
@Observable
final class AppModel {
    private(set) var profiles: [ConnectionProfile] = []
    var selectedID: UUID? {
        didSet {
            guard oldValue != selectedID else { return }
            persist()
            refreshMiddleware()  // each connection may name its own PKCS#11 module
            checkGateway(force: true)
        }
    }

    /// Profile shown in the editor sheet; `nil` when the sheet is closed.
    var editing: ProfileEditorModel?
    var isImportingRDP = false
    /// Error shown in an alert.
    var alert: AppAlert?

    let session = SessionController()
    let cards = CardMonitor()
    private let donation = DonationPrompt()
    /// The one-time offer to support the author is shown (after a disconnect, see `DonationPrompt`).
    private(set) var showsDonationOffer = false
    private var sessionReachedDesktop = false
    /// The last check of the selected connection's gateway while idle (`nil`: none or not done).
    private(set) var gatewayStatus: GatewayReachability?
    private var gatewayCheck: Task<Void, Never>?
    private var gatewaySchedule = GatewayCheckSchedule()
    private let networkMonitor = NWPathMonitor()
    /// Status and interfaces of the network as last reported, to react only to real changes.
    private var networkSignature: String?
    private var networkSettling: Task<Void, Never>?
    /// The remote desktop was shown, and the session ended (with or without reaching it).
    var onDesktopShown: (() -> Void)?
    var onClientEnded: (() -> Void)?
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
        session.onConnected = { [weak self] in
            self?.sessionReachedDesktop = true
            self?.gatewayCheck?.cancel()  // a result from before the connection is outdated
            self?.gatewayStatus = .reachable  // the connection just proved it
            self?.donation.recordSuccessfulConnection()
            self?.onDesktopShown?()
        }
        session.onEnded = { [weak self] end in
            guard let self else { return }
            defer { sessionReachedDesktop = false }
            onClientEnded?()
            // Only after a normal disconnect from a working session, never after an error.
            if sessionReachedDesktop, end == .closedByUser, donation.isDue() { showsDonationOffer = true }
            // After an error the gateway may be the reason; a normal end needs no check. Not after
            // "gateway unreachable": the port may answer while HTTPS fails (e.g. a middlebox that
            // resets TLS), and the check would clear the error the user has just been shown.
            if end != .closedByUser, end != .failed(.gatewayUnreachable) { checkGateway(force: true) }
        }
        // Network changes (Wi-Fi off, cable plugged in, VPN, another Wi-Fi network – its router
        // differs) may change whether the gateway is reachable.
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let interfaces = path.availableInterfaces.map(\.name).sorted().joined(separator: ",")
            let routers = path.gateways.map { "\($0)" }.sorted().joined(separator: ",")
            let signature = "\(path.status) \(interfaces) \(routers)"
            Task { @MainActor in self?.networkChanged(signature) }
        }
        networkMonitor.start(queue: .main)
    }

    /// Re-checks the gateway when the network really changed (a network came or went, another
    /// interface), once it settles – a flapping Wi-Fi or VPN must not start a check on every report.
    /// The first report at launch only records the state: the start already checks.
    private func networkChanged(_ signature: String) {
        defer { networkSignature = signature }
        guard let previous = networkSignature, previous != signature else { return }
        networkSettling?.cancel()
        networkSettling = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.checkGateway(force: true)
        }
    }

    /// Checks in the background whether the selected connection's gateway port can be reached
    /// (`GatewayReachability`, scheduled by `GatewayCheckSchedule`), so a problem with the internet,
    /// the address or a firewall shows before Connect. Never while connected.
    func checkGateway(force: Bool = false) {
        #if DEBUG
            // Screenshots and UI tests use example addresses that never answer.
            let environment = ProcessInfo.processInfo.environment
            if environment["CARDGATE_DEMO_CARD"] != nil || environment["CARDGATE_NO_GATEWAY_CHECK"] != nil { return }
        #endif
        guard !session.isRunning else { return }
        let gateway = selectedProfile?.gateway
        let decision = gatewaySchedule.decide(gateway: gateway, force: force)
        if decision.resetStatus {
            gatewayCheck?.cancel()
            gatewayStatus = nil
        }
        guard decision.check, let gateway else { return }
        gatewayCheck?.cancel()
        gatewayCheck = Task { [weak self] in
            let result = await GatewayReachability.probe(gateway)
            guard !Task.isCancelled, let self, self.selectedProfile?.gateway == gateway, !self.session.isRunning
            else { return }
            let text = String(describing: result)
            self.logger.info("Gateway port \(gateway, privacy: .public): \(text, privacy: .public)")
            self.gatewayStatus = result
            // A failed attempt that said the gateway is unreachable is outdated once it is back.
            if result == .reachable, self.session.phase == .ended(.failed(.gatewayUnreachable)) {
                self.session.clearFinished()
            }
        }
    }

    /// The support offer was used or closed; it is never shown again.
    func finishDonationOffer(openingPage: Bool) {
        showsDonationOffer = false
        donation.finish()
        if openingPage { NSWorkspace.shared.open(ProjectLinks.donation) }
    }

    /// Everything needed to connect is in place.
    /// Connect is possible while the card check still runs; connecting then waits for its result.
    var isReadyToConnect: Bool {
        middleware != nil && !moduleUntrusted && signInCertificate != nil && !session.isRunning
            && !cardNeedsReinsert && !isPreparingConnection
    }

    /// The certificate the selected connection signs in with.
    var signInCertificate: CardCertificate? {
        cards.signInCertificate(preferredSHA1: selectedProfile?.certificateSHA1)
    }

    /// Connect was clicked and waits for the card check to finish.
    private(set) var isPreparingConnection = false

    /// The configured PKCS#11 module is not validly code signed and is therefore not loaded.
    private(set) var moduleUntrusted = false

    /// The system lists the card but the middleware's PKCS#11 module does not see it.
    var cardNeedsReinsert: Bool {
        cards.pkcs11State == .noToken && !cards.certificates.isEmpty
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
        let selectionChanges = selectedID != profile.id
        selectedID = profile.id
        editing = nil
        persist()
        if !selectionChanges {
            // The same connection was edited: its module or gateway may have changed. (A newly
            // selected one is handled by `selectedID`.)
            refreshMiddleware()
            checkGateway(force: true)
        }
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
        var module = locator.resolve(configured: selectedProfile?.pkcs11Module)
        // The module is loaded into the client: accept only intact, signed code.
        moduleUntrusted = module.map { !CodeSignature.isValid(atPath: $0) } ?? false
        if moduleUntrusted { module = nil }
        middleware =
            locator.installed.first { $0.modulePath == module }
            ?? module.map { .init(name: URL(filePath: $0).lastPathComponent, modulePath: $0, downloadURL: nil) }
        cards.module = middleware?.modulePath
    }

    func connect() {
        guard let profile = selectedProfile, !isPreparingConnection else { return }
        refreshMiddleware()
        guard let module = middleware?.modulePath else {
            alert = .noMiddleware
            return
        }
        let executable = FreeRDPCommand.client(in: Bundle.main.bundleURL)
        guard let clientConfig, FileManager.default.isExecutableFile(atPath: executable.path(percentEncoded: false))
        else {
            alert = .clientMissing
            return
        }
        isPreparingConnection = true
        Task {
            defer { isPreparingConnection = false }
            // The card check (PKCS#11) may still run right after inserting the card or starting.
            let card = await cards.currentState()
            if card?.state == .noToken { return }
            guard let certificate = signInCertificate else { return }
            do {
                try clientConfig.install(for: profile)
                let command = try FreeRDPCommand(
                    executable: executable, profile: profile, pkcs11Module: module,
                    config: clientConfig, askPass: PINPrompt.command(module: module), screen: .current,
                    certificateSHA1: certificate.sha1, smartCardReader: card?.reader)
                session.connect(command, gateway: profile.gateway)
            } catch {
                logger.error("Cannot start client: \(error, privacy: .public)")
                alert = .clientMissing
            }
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

/// Code signature check of libraries loaded into the RDP client (PKCS#11 modules).
enum CodeSignature {
    static func isValid(atPath path: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(filePath: path) as CFURL, [], &code) == errSecSuccess, let code
        else { return false }
        return SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil)
            == errSecSuccess
    }
}
