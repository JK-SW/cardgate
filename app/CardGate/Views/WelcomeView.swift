import CardGateKit
import SwiftUI

/// First start: no connection is set up yet.
struct WelcomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        FillingScrollView {
            content
        }
        .toolbar { AppToolbar() }
        .toolbar(removing: .title)
    }

    private var content: some View {
        // Fits the smallest window without scrolling (unless a card module problem is shown).
        VStack(spacing: 16) {
            AppIllustration(width: 96)
            VStack(spacing: 8) {
                Text("Welcome to CardGate")
                    .font(.largeTitle.weight(.bold))
                Text("Connect to your work computer with your smart card.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 0) {
                WelcomeCardStep()
                Divider().padding(.leading, 36)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    StepNumber(number: 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Set up the connection")
                            .fontWeight(.semibold)
                        Text("Your IT department gives you the addresses of the computer and the gateway.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 10)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .frame(maxWidth: 440)
            .background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
            if case .moduleProblem(let problem) = model.cardReadiness {
                ModuleProblemView(problem: problem)
                    .frame(maxWidth: 440)
            }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button {
                    model.beginNewProfile()
                } label: {
                    Text("Set Up Connection")
                        .frame(minWidth: 240)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.extraLarge)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("welcome.setUp")

                Button("Import .rdp File…") { model.isImportingRDP = true }
                    .buttonStyle(.link)
            }
        }
        .padding(.horizontal, 32)
        .padding(.top, 4)
        .padding(.bottom, 20)
    }
}

/// The first step: a card that can sign in (or what is missing).
private struct WelcomeCardStep: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let readiness = model.cardReadiness
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if let symbol = readiness.tone.symbol {
                StepIcon(systemImage: symbol, tone: readiness.tone)
            } else if readiness.tone == .info {
                ProgressView().controlSize(.small).frame(width: 24)
            } else {
                StepNumber(number: 1)
            }
            VStack(alignment: .leading, spacing: 2) {
                details(readiness)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func details(_ readiness: CardReadiness) -> some View {
        switch readiness {
        case .ready(let certificate, let days, _):
            Text("Card ready: \(certificate.holderName)")
                .fontWeight(.semibold)
            if days != nil {
                readiness.title
                    .font(.callout)
                    .foregroundStyle(.orange)
                if let advice = readiness.advice {
                    advice
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if let notAfter = certificate.notAfter {
                Text("Certificate valid until \(notAfter.formatted(date: .long, time: .omitted))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        default:
            readiness.title
                .fontWeight(.semibold)
            if case .noMiddleware = readiness {
                MiddlewareDownloadLink()
            } else if let advice = readiness.advice {
                advice
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct StepNumber: View {
    let number: Int

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tint)
            .frame(width: 24, height: 24)
            .background(Color.accentColor.opacity(0.14), in: Circle())
            .accessibilityHidden(true)
    }
}

private struct StepIcon: View {
    let systemImage: String
    let tone: StatusTone

    var body: some View {
        Image(systemName: systemImage)
            .font(.caption.weight(.bold))
            .foregroundStyle(tone.color)
            .frame(width: 24, height: 24)
            .background(tone.background, in: Circle())
            .accessibilityHidden(true)
    }
}
