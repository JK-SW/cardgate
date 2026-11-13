import Foundation

/// A problem the app reports in an alert (the texts are in the app's views).
public enum AppAlert: Identifiable, Hashable, Sendable {
    /// The file could not be read or backed up; nothing is saved over it.
    case profilesNotReadable
    /// Nothing could be read; the file was moved to `backup`.
    case profilesUnreadable(backup: String)
    /// Some connections could not be read; the file as it was is in `backup`.
    case profilesPartlyUnreadable(skipped: Int, backup: String)
    case profilesFromNewerVersion
    case profilesNotSaved
    case rdpUnreadable
    case noMiddleware
    case clientMissing
    case clientSettingsNotSaved
    case modulePathUnusable
    case gatewayMissing

    public var id: Self { self }

    /// The alert for a problem while loading the connections; paths are shown with `~`.
    public init(_ problem: ProfileStore.LoadProblem) {
        func shown(_ url: URL) -> String {
            (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
        }
        self =
            switch problem {
            case .unreadable(let backup): .profilesUnreadable(backup: shown(backup))
            case .partlyUnreadable(let skipped, let backup):
                .profilesPartlyUnreadable(skipped: skipped, backup: shown(backup))
            case .newerVersion: .profilesFromNewerVersion
            case .notSaved: .profilesNotReadable
            }
    }

    /// The alert for a client command that cannot be built.
    public init(_ error: FreeRDPCommand.BuildError) {
        self =
            switch error {
            case .gatewayRequired: .gatewayMissing
            case .invalidModulePath: .modulePathUnusable
            }
    }
}
