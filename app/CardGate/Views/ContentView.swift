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
        case .profilesNotSaved: "Connections could not be saved"
        case .rdpUnreadable: "The file cannot be imported"
        case .noMiddleware: "Smart card software is missing"
        case .clientMissing: "The remote desktop client cannot be started"
        }
    }

    var message: LocalizedStringKey {
        switch self {
        case .profilesUnreadable:
            "The file with your connections is damaged. You can set up the connection again."
        case .profilesNotSaved:
            "Your changes will be lost when the app quits. Check the free disk space."
        case .rdpUnreadable:
            "It is not a valid Remote Desktop file or it does not contain a computer address."
        case .noMiddleware:
            "Install the software for your smart card (for example ProID+) and try again."
        case .clientMissing:
            "The application is incomplete. Download and install it again."
        }
    }
}
