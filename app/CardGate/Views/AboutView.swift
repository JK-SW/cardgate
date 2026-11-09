import SwiftUI

/// About window: version, author, license and the third-party notices.
struct AboutView: View {
    @State private var showsNotices = false

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("CardGate")
                    .font(.title.weight(.semibold))
                Text("Version \(version)")
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Text("Remote desktop through an RD Gateway with smart card sign-in.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("Author: \("Ing. Jiří Kubínek")")
                Text("Licensed under the Apache License 2.0.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            HStack(spacing: 16) {
                if let url = URL(string: "https://github.com/JK-SW/cardgate") {
                    Link("Source Code", destination: url)
                }
                Button("Third-Party Licenses") { showsNotices = true }
                    .buttonStyle(.link)
            }
            .font(.callout)
        }
        .padding(28)
        .frame(width: 380)
        .sheet(isPresented: $showsNotices) { NoticesView() }
    }
}

private struct NoticesView: View {
    @Environment(\.dismiss) private var dismiss

    private var text: String {
        guard let url = Bundle.main.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return String(localized: "The license texts are missing from this build.") }
        return text
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
            Divider()
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 640, height: 520)
    }
}
