import CardGateKit
import SwiftUI

/// The selected connection at a glance: the card, the gateway and the sign-in certificate, each
/// with its state.
struct ConnectionOverview: View {
    @Environment(AppModel.self) private var model
    let profile: ConnectionProfile
    let readiness: CardReadiness

    var body: some View {
        VStack(spacing: 0) {
            OverviewRow(label: Text("Card")) {
                cardValue
            } status: {
                cardStatus
            }
            Divider()
            OverviewRow(label: Text("Gateway")) {
                if let gateway = profile.gateway {
                    Text(gateway.description)
                        .textSelection(.enabled)
                } else {
                    Text("Not set")
                        .foregroundStyle(.secondary)
                }
            } status: {
                gatewayStatus
            }
            if case .ready(let certificate, _, _) = readiness, let notAfter = certificate.notAfter {
                Divider()
                OverviewRow(label: Text("Certificate")) {
                    Text("Valid until \(notAfter.formatted(date: .long, time: .omitted))")
                } status: {
                    if let expiry = readiness.expiryShort {
                        OverviewStatus(tone: .warning, text: expiry)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview")
    }

    @ViewBuilder private var cardValue: some View {
        if case .ready(let certificate, _, _) = readiness {
            Text(certificate.holderName)
        } else {
            readiness.summary
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var cardStatus: some View {
        HStack(spacing: 8) {
            // A check of a ready card runs next to its state: Connect stays possible meanwhile.
            CardCheckIndicator()
            if case .ready = readiness {
                // Orange with a certificate that expires soon, like the card in the sidebar.
                OverviewStatus(tone: readiness.tone, text: Text("Ready"), identifier: "overview.cardReady")
            } else if readiness.tone != .neutral && readiness.tone != .info {
                OverviewStatus(tone: readiness.tone, text: nil)
            }
        }
    }

    @ViewBuilder private var gatewayStatus: some View {
        if profile.gateway == nil {
            OverviewStatus(tone: .warning, text: nil)
        } else if model.shownGatewayStatus == .reachable {
            OverviewStatus(tone: .success, text: Text("Reachable"))
        } else if model.shownGatewayStatus == .unreachable {
            OverviewStatus(tone: .warning, text: Text("Unreachable"))
        }
    }
}

private struct OverviewRow<Value: View, Status: View>: View {
    let label: Text
    @ViewBuilder var value: Value
    @ViewBuilder var status: Status

    var body: some View {
        HStack(spacing: 10) {
            label
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            value
                .fontWeight(.medium)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            status
        }
        .font(.callout)
        .padding(.vertical, 9)
    }
}

/// A colored dot, with a word when the value alone does not say it.
private struct OverviewStatus: View {
    let tone: StatusTone
    let text: Text?
    var identifier = ""

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tone.color)
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            if let text {
                text
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tone.color)
                    .accessibilityIdentifier(identifier)
            }
        }
        .fixedSize()
    }
}
