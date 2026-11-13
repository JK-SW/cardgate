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
                if editor.isImported {
                    Section {
                        Label(
                            """
                            Connect only to addresses you got from your IT department. While connected, the \
                            remote computer can use your smart card.
                            """,
                            systemImage: "exclamationmark.shield.fill"
                        )
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("profile.importWarning")
                    } header: {
                        Text("Check the imported connection")
                    }
                }
                Section {
                    TextField("Name", text: $editor.name)
                        .accessibilityIdentifier("profile.name")
                    TextField("Computer", text: $editor.computer, prompt: Text("pc01.example.com"))
                        .textContentType(.URL)
                        .accessibilityIdentifier("profile.computer")
                    validation(editor.computerError, empty: "Enter the address of your work computer.")
                    TextField("Gateway", text: $editor.gateway, prompt: Text("rdg.example.com"))
                        .textContentType(.URL)
                        .accessibilityIdentifier("profile.gateway")
                    validation(editor.gatewayError, empty: "Enter the address of the RD Gateway.")
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
                    .accessibilityIdentifier("profile.displayMode")
                    if editor.displayMode == .window {
                        Picker("Initial window size", selection: $editor.windowSize) {
                            Text("Automatic").tag(WindowSize?.none)
                            ForEach(sizes, id: \.self) { size in
                                Text(size.description).tag(Optional(size))
                            }
                        }
                        .accessibilityIdentifier("profile.windowSize")
                    }
                    Picker("Scale", selection: $editor.scale) {
                        Text("Automatic").tag(Int?.none)
                        ForEach(scales, id: \.self) { scale in
                            Text(Self.percent(scale)).tag(Optional(scale))
                        }
                    }
                    .help("Size of text and apps on the remote desktop.")
                    .accessibilityIdentifier("profile.scale")
                }

                Section("Sharing") {
                    Toggle("Clipboard", isOn: $editor.clipboard)
                        .accessibilityIdentifier("profile.clipboard")
                    Toggle("Play sound on this Mac", isOn: $editor.audio)
                        .accessibilityIdentifier("profile.audio")
                }

                Section {
                    Picker("Sign-in certificate", selection: $editor.certificateSHA1) {
                        Text("Automatic (newest valid)").tag(String?.none)
                        ForEach(certificateChoices) { certificate in
                            Text(label(for: certificate)).tag(Optional(certificate.sha1))
                        }
                        if let chosen = editor.certificateSHA1,
                            !certificateChoices.contains(where: { $0.sha1 == chosen })
                        {
                            Text("Certificate not on the inserted card").tag(Optional(chosen))
                        }
                    }
                } header: {
                    Text("Card")
                } footer: {
                    Text("Choose a certificate only if your card holds several valid sign-in certificates.")
                        .foregroundStyle(.secondary)
                }

                Section("Mouse") {
                    Toggle("Scroll in the same direction as on this Mac", isOn: $editor.scrollLikeThisMac)
                }

                Section {
                    TextField("PKCS#11 module", text: $editor.pkcs11Module, prompt: Text("Automatic"))
                        .accessibilityIdentifier("profile.module")
                    if !editor.moduleIsValid {
                        Text("Enter the full path of the module, starting with /, without commas.")
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
        .frame(minHeight: 600)
        .confirmationDialog("Delete this connection?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let profile = model.profiles.first(where: { $0.id == editor.id }) { model.delete(profile) }
            }
        }
    }

    /// Valid sign-in certificates of the inserted card.
    private var certificateChoices: [CardCertificate] {
        CardCertificate.signInCandidates(in: model.cards.certificates, at: Date())
    }

    private func label(for certificate: CardCertificate) -> String {
        guard let notAfter = certificate.notAfter else { return certificate.holderName }
        return String(
            localized:
                "\(certificate.holderName) – valid until \(notAfter.formatted(date: .abbreviated, time: .omitted))")
    }

    /// Presets that fit on this display, plus the current size if it is a custom one
    /// (e.g. imported from an .rdp file).
    private var sizes: [WindowSize] {
        let screen = ScreenMetrics.current
        var sizes = WindowSize.presets.filter { screen?.fits($0) ?? true }
        if let current = editor.windowSize, !sizes.contains(current) { sizes.insert(current, at: 0) }
        return sizes
    }

    /// Presets plus the current scale if it is another valid one (from a profile edited by hand).
    private var scales: [Int] {
        var scales = DisplaySettings.scalePresets
        if let current = editor.scale, !scales.contains(current) {
            scales.append(current)
            scales.sort()
        }
        return scales
    }

    private static func percent(_ scale: Int) -> String {
        (Double(scale) / 100).formatted(.percent)
    }

    @ViewBuilder
    private func validation(_ error: HostAddress.ParseError?, empty: LocalizedStringKey) -> some View {
        switch error {
        case nil:
            EmptyView()
        case .empty:
            Text(empty).foregroundStyle(.secondary).font(.callout)
        case .invalidHost:
            Text("Enter a name like pc01.example.com, without spaces or other characters.")
                .foregroundStyle(.red).font(.callout)
        case .invalidPort:
            Text("The port after the colon must be a number between 1 and 65535.")
                .foregroundStyle(.red).font(.callout)
        }
    }
}
