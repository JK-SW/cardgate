import CardGateKit
import SwiftUI

/// Sheet for creating or editing a connection.
struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Bindable var editor: ProfileEditorModel
    @State private var confirmDelete = false

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $editor.name)
                    TextField("Computer", text: $editor.computer, prompt: Text("pc01.example.com"))
                        .textContentType(.URL)
                    validation(editor.computerError, empty: "Enter the address of your work computer.")
                    TextField("Gateway", text: $editor.gateway, prompt: Text("Optional"))
                        .textContentType(.URL)
                    validation(editor.gatewayError, empty: nil)
                } header: {
                    Text("Connection")
                } footer: {
                    Text("You get both addresses from your IT department or from its .rdp file.")
                        .foregroundStyle(.secondary)
                }

                Section("Display") {
                    Picker("Show as", selection: $editor.displayMode) {
                        Text("Window").tag(DisplaySettings.Mode.window)
                        Text("Full screen").tag(DisplaySettings.Mode.fullScreen)
                        Text("Full screen on all displays").tag(DisplaySettings.Mode.allDisplays)
                    }
                    if editor.displayMode == .window {
                        Picker("Initial window size", selection: $editor.windowSize) {
                            Text("Automatic").tag(WindowSize?.none)
                            ForEach(sizes, id: \.self) { size in
                                Text(size.description).tag(Optional(size))
                            }
                        }
                    }
                }

                Section("Sharing") {
                    Toggle("Clipboard", isOn: $editor.clipboard)
                    Toggle("Play sound on this Mac", isOn: $editor.audio)
                }

                Section("Mouse") {
                    Toggle("Scroll in the same direction as on this Mac", isOn: $editor.scrollLikeThisMac)
                }

                Section {
                    TextField("PKCS#11 module", text: $editor.pkcs11Module, prompt: Text("Automatic"))
                    if !editor.moduleIsValid {
                        Text("Enter the full path of the module, starting with /.")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                } header: {
                    Text("Advanced")
                } footer: {
                    Text("Leave empty unless your IT department tells you otherwise.")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !editor.isNew {
                    Button("Delete Connection…", role: .destructive) { confirmDelete = true }
                }
                Spacer()
                Button("Cancel", role: .cancel) { model.editing = nil }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let profile = editor.makeProfile() { model.save(profile) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!editor.canSave)
            }
            .padding()
        }
        .frame(width: 480)
        .frame(minHeight: 560)
        .confirmationDialog("Delete this connection?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let profile = model.profiles.first(where: { $0.id == editor.id }) { model.delete(profile) }
            }
        }
    }

    /// Presets plus the current size if it is a custom one (e.g. imported from an .rdp file).
    private var sizes: [WindowSize] {
        var sizes = WindowSize.presets
        if let current = editor.windowSize, !sizes.contains(current) { sizes.insert(current, at: 0) }
        return sizes
    }

    @ViewBuilder
    private func validation(_ error: HostAddress.ParseError?, empty: LocalizedStringKey?) -> some View {
        switch error {
        case nil:
            EmptyView()
        case .empty:
            if let empty { Text(empty).foregroundStyle(.secondary).font(.callout) }
        case .invalidHost:
            Text("Enter a name like pc01.example.com, without spaces or other characters.")
                .foregroundStyle(.red).font(.callout)
        case .invalidPort:
            Text("The port after the colon must be a number between 1 and 65535.")
                .foregroundStyle(.red).font(.callout)
        }
    }
}
