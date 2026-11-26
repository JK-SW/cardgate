import CardGateKit
import Foundation
import Observation
import Sparkle

/// Checks for and installs new versions (Sparkle).
///
/// The feed is published with every GitHub Release and each archive is signed with the project's
/// EdDSA key (the public half is `SUPublicEDKey` in Info.plist), so only genuine updates are
/// installed. Sparkle asks the user once whether to check automatically; a check only downloads
/// the feed and sends nothing about the user. Builds without a public key (local development)
/// never check.
@MainActor
@Observable
final class Updater {
    private let controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?
    private(set) var canCheckForUpdates = false
    private var automaticChecksObservation: NSKeyValueObservation?
    /// The setting in CardGate → Settings (Sparkle also asks once, on the second launch).
    var automaticallyChecksForUpdates = false {
        didSet {
            guard let updater = controller?.updater,
                updater.automaticallyChecksForUpdates != automaticallyChecksForUpdates
            else { return }
            updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    init() {
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? ""
        guard !key.trimmingCharacters(in: .whitespaces).isEmpty else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(
            startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        canCheckForUpdates = controller.updater.canCheckForUpdates
        observation = controller.updater.observe(\.canCheckForUpdates, options: [.new]) { [weak self] _, change in
            let canCheck = change.newValue ?? false
            Task { @MainActor in self?.canCheckForUpdates = canCheck }
        }
        automaticallyChecksForUpdates = controller.updater.automaticallyChecksForUpdates
        automaticChecksObservation = controller.updater.observe(
            \.automaticallyChecksForUpdates, options: [.new]
        ) { [weak self] _, _ in
            // Read the current value when the task runs, never a queued older one.
            Task { @MainActor in
                if let self, let updater = self.controller?.updater {
                    self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
                }
            }
        }
    }

    var isAvailable: Bool { controller != nil }

    /// The update settings and the last check, for the diagnostic information of the saved log.
    var diagnostics: [(String, String)] {
        let sparkle = Bundle(for: SPUUpdater.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        guard let updater = controller?.updater else {
            return [("Updates", "not available in this build"), ("Sparkle", sparkle)]
        }
        let skipped = ["SUSkippedMinorVersion", "SUSkippedMajorVersion"].compactMap {
            UserDefaults.standard.string(forKey: $0)
        }
        return [
            ("Automatic checks", DiagnosticReport.yesNo(updater.automaticallyChecksForUpdates)),
            ("Automatic downloads", DiagnosticReport.yesNo(updater.automaticallyDownloadsUpdates)),
            ("Check interval", "\(Int(updater.updateCheckInterval / 3600)) h"),
            ("Last check", updater.lastUpdateCheckDate.map { DiagnosticReport.time($0) } ?? "never"),
            ("Skipped version", skipped.isEmpty ? "-" : skipped.joined(separator: ", ")),
            ("Feed", updater.feedURL?.absoluteString ?? "?"),
            ("Sparkle", sparkle),
        ]
    }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}
