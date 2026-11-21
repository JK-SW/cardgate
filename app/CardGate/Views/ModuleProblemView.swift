import CardGateKit
import SwiftUI

/// The card module of the connection cannot be used as it is: missing, or waiting for approval.
struct ModuleProblemView: View {
    @Environment(AppModel.self) private var model
    let problem: ModuleProblem
    @State private var confirming = false

    var body: some View {
        Group {
            switch problem {
            case .configuredMissing(let path):
                NoticeView(
                    tone: .warning, systemImage: "exclamationmark.triangle.fill",
                    title: Text("The smart card module set for this connection was not found."),
                    message: Text(
                        "Check the module path in the connection settings (section Advanced), or leave it empty.")
                ) {
                    pathText(path)
                    editButton
                }
            case .invalidSignature(let path):
                NoticeView(
                    tone: .error, systemImage: "xmark.shield.fill",
                    title: Text("The smart card module was changed after it was signed."),
                    message: Text("It is not loaded. Install the card software again or contact your IT department.")
                ) {
                    pathText(path)
                    if isConfigured { editButton }
                }
            case .unreadable(let path):
                NoticeView(
                    tone: .error, systemImage: "xmark.shield.fill",
                    title: Text("The smart card module cannot be read."),
                    message: Text(
                        """
                        Check that the file exists and that you may read it, or install the card software again. \
                        A module set in the connection can be changed in its settings.
                        """)
                ) {
                    pathText(path)
                    if isConfigured { editButton }
                }
            case .needsApproval(let path, let sha256):
                NoticeView(
                    tone: .warning, systemImage: "exclamationmark.shield.fill",
                    title: Text("The smart card module is not from a verified publisher."),
                    message: Text(
                        "It gets your PIN and access to the card. Use it only if you got it from your IT department.")
                ) {
                    pathText(path)
                    Button("Use This Module…") { confirming = true }
                        .disabled(model.isBusy)
                        .padding(.top, 4)
                        .accessibilityIdentifier("module.approve")
                        .alert("Use a module from an unverified publisher?", isPresented: $confirming) {
                            Button("Use Module", role: .destructive) { model.approveModule(path: path, sha256: sha256) }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text(
                                """
                                CardGate cannot verify who made \(URL(filePath: path).lastPathComponent). A harmful \
                                module could misuse your PIN and card. CardGate asks again if the file changes.
                                """)
                        }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("moduleProblem")
    }

    private func pathText(_ path: String) -> some View {
        Text(verbatim: (path as NSString).abbreviatingWithTildeInPath)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
    }

    /// The module comes from the connection's settings (not found automatically).
    private var isConfigured: Bool {
        !(model.selectedProfile?.pkcs11Module ?? "").isEmpty
    }

    @ViewBuilder private var editButton: some View {
        if let profile = model.selectedProfile {
            Button("Edit Connection") { model.beginEditing(profile) }
                .disabled(model.isBusy)
                .padding(.top, 4)
        }
    }
}
