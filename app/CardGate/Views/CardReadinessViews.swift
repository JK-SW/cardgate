import CardGateKit
import SwiftUI

extension CardReadiness {
    /// A few words for the card in the sidebar.
    var summary: Text {
        switch self {
        case .moduleProblem(.needsApproval): Text("Card module needs approval")
        case .moduleProblem(.configuredMissing): Text("Card module not found")
        case .moduleProblem: Text("Card module cannot be used")
        case .noMiddleware: Text("Card software missing")
        case .needsReinsert: Text("Insert the card again")
        case .ready(_, nil, _): Text("Card ready")
        case .ready: Text("Certificate expires soon")
        case .expired: Text("Certificate expired")
        case .reading: Text("Reading the card…")
        case .noCard: Text("No card")
        case .noSignInCertificate: Text("No sign-in certificate")
        }
    }

    /// What the notice and the welcome screen say; for a ready card, when its certificate expires soon.
    var title: Text {
        switch self {
        case .noMiddleware: Text("No smart card software found")
        case .needsReinsert: Text("The card is not available to sign in.")
        case .ready(_, 0, _): Text("The sign-in certificate expires today.")
        case .ready(_, let days?, _): Text("The sign-in certificate expires in \(days) days.")
        case .expired: Text("The sign-in certificate on the card has expired.")
        case .noCard: Text("Insert your card or token.")
        case .noSignInCertificate: Text("The inserted card has no certificate for signing in.")
        // A module problem is explained by `ModuleProblemView`, with the module's path and what to do.
        case .moduleProblem, .ready, .reading: summary
        }
    }

    /// A few words when the certificate expires soon (the overview's Certificate row).
    var expiryShort: Text? {
        switch self {
        case .ready(_, 0, _): Text("Expires today")
        case .ready(_, let days?, _): Text("Expires in \(days) days")
        default: nil
        }
    }

    /// What to do about it.
    var advice: Text? {
        switch self {
        case .needsReinsert: Text("Remove the card or token and insert it again.")
        case .ready(_, .some, true):
            Text("A renewed certificate is on the card: choose it in the connection settings (section Advanced).")
        case .ready(_, .some, false): Text("Ask your IT department to renew it in time.")
        case .expired: Text("Contact your IT department to renew it.")
        default: nil
        }
    }

    private var systemImage: String {
        switch self {
        case .ready, .expired: "calendar.badge.exclamationmark"
        case .noCard: "creditcard"
        default: "exclamationmark.triangle.fill"
        }
    }

    /// Nothing to tell while the card is ready (apart from a certificate that expires soon) or read.
    var needsNotice: Bool {
        switch self {
        case .ready(_, nil, _), .reading: false
        default: true
        }
    }

    @MainActor fileprivate var notice: NoticeView<EmptyView> {
        NoticeView(tone: tone, systemImage: systemImage, title: title, message: advice)
    }
}

/// The link to the card software a user most likely needs.
struct MiddlewareDownloadLink: View {
    var body: some View {
        if let url = PKCS11ModuleLocator.knownMiddleware.first?.downloadURL {
            Link("Download ProID+", destination: url)
                .font(.callout.weight(.semibold))
        }
    }
}

/// What to do about the card.
struct CardNoticeView: View {
    let readiness: CardReadiness

    var body: some View {
        switch readiness {
        case .moduleProblem(let problem):
            ModuleProblemView(problem: problem)
        case .noMiddleware:
            NoticeView(tone: readiness.tone, systemImage: "exclamationmark.triangle.fill", title: readiness.title) {
                MiddlewareDownloadLink()
            }
        default:
            if readiness.needsNotice {
                readiness.notice
            }
        }
    }
}

/// The card at the bottom of the sidebar: whose it is and whether it can be used.
struct CardStatusTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let readiness = model.cardReadiness
        HStack(spacing: 10) {
            Image(systemName: "creditcard.fill")
                .font(.title3)
                .foregroundStyle(
                    readiness.tone == .neutral ? AnyShapeStyle(.tertiary) : AnyShapeStyle(readiness.tone.color)
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                if case .ready(let certificate, _, _) = readiness {
                    Text(certificate.holderName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                } else {
                    Text("Smart Card")
                        .font(.callout.weight(.semibold))
                }
                readiness.summary
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            badge(readiness)
        }
        .padding(10)
        .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("cardStatus")
    }

    @ViewBuilder private func badge(_ readiness: CardReadiness) -> some View {
        if model.isCardActive {
            CardCheckIndicator()
        } else if let symbol = readiness.tone.symbol {
            Image(systemName: "\(symbol).circle.fill").foregroundStyle(readiness.tone.color)
        }
    }
}

/// A spinner while the card is read or checked.
struct CardCheckIndicator: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.isCardActive {
            ProgressView().controlSize(.small)
                .help(model.cards.isChecking ? Text("Checking the card…") : Text("Reading the card…"))
        }
    }
}
