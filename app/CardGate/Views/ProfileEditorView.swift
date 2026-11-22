import CardGateKit
import SwiftUI

/// Sheet for creating or editing a connection.
struct ProfileEditorView: View {
    @Environment(AppModel.self) private var model
    @Bindable var editor: ProfileEditorModel
    @State private var confirmDelete = false
    /// Displays connected now (updated when they change), for the full screen display.
    @State private var displays: [ConnectedDisplay] = []
    /// Open when the connection already uses an advanced setting; only the user closes it.
    @State private var showAdvanced: Bool

    init(editor: ProfileEditorModel) {
        self.editor = editor
        _showAdvanced = State(initialValue: editor.usesAdvancedSettings)
    }

    /// A whole row that opens and closes the advanced settings, like the rows of System Settings.
    private var advancedToggle: some View {
        Button {
            withAnimation { showAdvanced.toggle() }
        } label: {
            HStack {
                Text("Advanced")
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(showAdvanced ? 90 : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.advanced")
        .accessibilityValue(showAdvanced ? Text("Shown") : Text("Hidden"))
    }

    /// Settings most connections never change.
    @ViewBuilder private var advancedSettings: some View {
        Picker("Sign-in certificate", selection: $editor.certificateSHA1) {
            Text("Automatic (newest valid)").tag(String?.none)
            ForEach(certificateChoices) { certificate in
                Text(label(for: certificate)).tag(Optional(certificate.sha1))
            }
            if let chosen = editor.certificateSHA1, !certificateChoices.contains(where: { $0.sha1 == chosen }) {
                Text("Certificate not on the inserted card").tag(Optional(chosen))
            }
        }
        .help("Choose a certificate only if your card holds several valid sign-in certificates.")

        Picker("Security", selection: $editor.security) {
            if let remembered = model.rememberedSecurity(for: editor.id) {
                Text("Automatic (\(remembered.shortName))").tag(ConnectionSecurity.automatic)
            } else {
                Text("Automatic").tag(ConnectionSecurity.automatic)
            }
            Text("NLA").tag(ConnectionSecurity.nla)
            Text("TLS").tag(ConnectionSecurity.tls)
            Text("RDP Security").tag(ConnectionSecurity.rdp)
        }
        .help(securityHelp)
        .accessibilityIdentifier("profile.security")

        Picker("Sign in to Windows", selection: $editor.windowsSignIn) {
            Text("With the card").tag(WindowsSignIn.smartCard)
            Text("With user name and password").tag(WindowsSignIn.password)
        }
        .help(
            """
            Choose user name and password if Windows on this computer does not accept \
            the card. The card still signs you in to the gateway.
            """
        )
        .accessibilityIdentifier("profile.windowsSignIn")
        if editor.windowsSignIn == .password {
            Text(
                """
                Windows shows its sign-in screen and asks for your password. The card still \
                signs you in to the gateway and stays available in Windows.
                """
            )
            .foregroundStyle(.secondary)
            .font(.callout)
        }

        if editor.keepSessionActiveAvailable {
            Toggle("Keep the session active when idle", isOn: $editor.keepSessionActive)
                .accessibilityIdentifier("profile.keepSessionActive")
            Text(
                """
                Bypasses the idle limits set in Windows: the session is neither disconnected nor \
                locked while you are away. Turn it on only where it is necessary and your IT \
                department allows it. Lock your Mac when you leave.
                """
            )
            .foregroundStyle(.secondary)
            .font(.callout)
        }

        TextField("PKCS#11 module", text: $editor.pkcs11Module, prompt: Text("Automatic"))
            .help("Leave empty unless your IT department tells you otherwise.")
            .accessibilityIdentifier("profile.module")
        if !editor.moduleIsValid {
            moduleError
        }
    }

    private var moduleError: some View {
        Text("Enter the full path of the module, starting with /, without commas.")
            .foregroundStyle(.red)
            .font(.callout)
    }

    /// Without the PIN promise when Windows asks for a password.
    private var securityHelp: Text {
        let automatic = Text("Automatic uses the strongest security the computer accepts and remembers it.")
        guard editor.windowsSignIn == .smartCard else { return automatic }
        let pin = Text("With NLA you do not enter the PIN a second time when signing in to Windows.")
        return automatic + Text(verbatim: " ") + pin
    }

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
                            Text("Automatic (\(Self.percent(ScreenMetrics.defaultWindowPercent)) of the screen)")
                                .tag(WindowSize?.none)
                            ForEach(sizes, id: \.self) { size in
                                Text(size.description).tag(Optional(size))
                            }
                        }
                        .accessibilityIdentifier("profile.windowSize")
                    }
                    if editor.displayMode == .fullScreen, displays.count > 1 || editor.fullScreenDisplay != nil {
                        Picker("Show on", selection: $editor.fullScreenDisplay) {
                            Text("Main display").tag(DisplayChoice?.none)
                            ForEach(displayOptions, id: \.self) { option in
                                Text(Self.label(option)).tag(Optional(option.choice))
                            }
                        }
                        .help("The display the remote desktop opens on in full screen.")
                        .accessibilityIdentifier("profile.fullScreenDisplay")
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

                Section("Sharing and Input") {
                    Toggle("Clipboard", isOn: $editor.clipboard)
                        .accessibilityIdentifier("profile.clipboard")
                    Toggle("Play sound on this Mac", isOn: $editor.audio)
                        .accessibilityIdentifier("profile.audio")
                    Toggle("Scroll in the same direction as on this Mac", isOn: $editor.scrollLikeThisMac)
                }

                Section {
                    advancedToggle
                    if showAdvanced {
                        advancedSettings
                    } else if !editor.moduleIsValid {
                        // Saving is blocked by a setting the closed section hides.
                        moduleError
                    }
                } footer: {
                    Text("Change these only if you need to or your IT department tells you so.")
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
        .onAppear { displays = ConnectedDisplay.current }
        .onReceive(Self.displaysChanged) { _ in displays = ConnectedDisplay.current }
        // Within the main window's smallest size (the form scrolls).
        .frame(height: 420)
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

    private var displayOptions: [ConnectedDisplay.Option] {
        ConnectedDisplay.options(chosen: editor.fullScreenDisplay, among: displays)
    }

    private static func label(_ option: ConnectedDisplay.Option) -> String {
        option.isConnected ? option.name : String(localized: "\(option.name) (not connected)")
    }

    private static let displaysChanged = NotificationCenter.default.publisher(
        for: NSApplication.didChangeScreenParametersNotification)

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
