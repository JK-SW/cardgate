import CardGateKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Group {
            if model.profiles.isEmpty {
                WelcomeView()
            } else {
                ConnectView()
            }
        }
        .sheet(item: $model.editing) { editor in
            ProfileEditorView(editor: editor)
        }
        .fileImporter(isPresented: $model.isImportingRDP, allowedContentTypes: [.rdpFile, .data]) { result in
            if case .success(let url) = result { model.importRDP(from: url) }
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshMiddleware()
            model.checkGateway()
        }
    }
}

extension UTType {
    /// Remote Desktop connection file saved by the Microsoft client.
    static let rdpFile = UTType(filenameExtension: "rdp") ?? .data
}

extension AppAlert {
    var title: LocalizedStringKey {
        switch self {
        case .profilesUnreadable: "Saved connections cannot be read"
        case .profilesPartlyUnreadable: "Some saved connections cannot be read"
        case .profilesFromNewerVersion: "Connections were saved by a newer CardGate"
        case .profilesNotReadable: "Saved connections cannot be read"
        case .profilesNotSaved: "Connections could not be saved"
        case .rdpUnreadable: "The file cannot be imported"
        case .noMiddleware: "Smart card software is missing"
        case .clientMissing, .clientSettingsNotSaved, .modulePathUnusable:
            "The remote desktop client cannot be started"
        case .gatewayMissing: "The connection has no gateway"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .profilesUnreadable(let backup):
            "The file with your connections is damaged. It was kept as \(backup). Set up the connection again."
        case .profilesPartlyUnreadable(let skipped, let backup):
            "Connections that could not be read are not shown (\(skipped)). The file as it was is kept as \(backup)."
        case .profilesNotReadable:
            """
            The file with your connections cannot be read or backed up. To keep it intact, changes \
            will not be saved. Restart CardGate; if this keeps happening, contact your IT department.
            """
        case .profilesFromNewerVersion:
            "Changes you make now will not be saved. Update CardGate to keep your connections up to date."
        case .profilesNotSaved:
            "Your changes will be lost when the app quits. Check the free disk space."
        case .rdpUnreadable:
            "It is not a valid Remote Desktop file or it does not contain a computer address."
        case .noMiddleware:
            "Install the software for your smart card (for example ProID+) and try again."
        case .clientMissing:
            "The application is incomplete. Download and install it again."
        case .clientSettingsNotSaved:
            "CardGate cannot save the settings for the connection. Check the free disk space."
        case .modulePathUnusable:
            """
            The path of the smart card software contains a comma or a line break. Move the module to \
            another folder or contact your IT department.
            """
        case .gatewayMissing:
            """
            CardGate connects only through an RD Gateway, which protects the connection and your PIN. \
            Add the gateway address in the connection settings.
            """
        }
    }
}
