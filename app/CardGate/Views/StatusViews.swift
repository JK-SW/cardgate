import CardGateKit
import SwiftUI

/// The colors are system colors, so they follow the dark mode.
extension StatusTone {
    /// The mark in a status badge (`nil`: no badge).
    var symbol: String? {
        switch self {
        case .success: "checkmark"
        case .warning: "exclamationmark"
        case .error: "xmark"
        case .info, .neutral: nil
        }
    }

    var color: Color {
        switch self {
        case .success: .green
        case .warning: .orange
        case .error: .red
        case .info: .accentColor
        case .neutral: .secondary
        }
    }

    /// A tinted background that keeps the text readable in light and dark mode.
    var background: Color {
        self == .neutral ? Color.secondary.opacity(0.12) : color.opacity(0.14)
    }
}

/// Content that fills the window's height (a Spacer pushes the buttons to the bottom) and scrolls
/// when it does not fit. Without the scroll view the wrapped notices would set the window's minimum
/// height, measured at the narrowest width, and push everything out of the window.
struct FillingScrollView<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

/// A notice with an icon, a title and advice: problems with the card, the gateway or the last attempt.
struct NoticeView<Accessory: View>: View {
    let tone: StatusTone
    /// `nil` with `inProgress`.
    let systemImage: String?
    let title: Text
    var message: Text?
    /// Shows a spinner instead of the icon (something is in progress).
    var inProgress = false
    @ViewBuilder var accessory: Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Group {
                if inProgress {
                    ProgressView().controlSize(.small)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(tone.color)
                }
            }
            .font(.title3)
            .frame(width: 22)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                title
                    .font(.callout.weight(.semibold))
                if let message {
                    message
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                accessory
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .multilineTextAlignment(.leading)
        .padding(12)
        .background(tone.background, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
    }
}

extension NoticeView where Accessory == EmptyView {
    init(tone: StatusTone, systemImage: String?, title: Text, message: Text? = nil, inProgress: Bool = false) {
        self.init(tone: tone, systemImage: systemImage, title: title, message: message, inProgress: inProgress) {
            EmptyView()
        }
    }
}

/// The steps of a connection attempt, the current one with a spinner.
struct ConnectionStepsView: View {
    let phase: SessionPhase

    private var current: Int { phase.connectionStep ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            step(0, "Start the client")
            step(1, "Card PIN", hint: "Enter the PIN of your card in the dialog.")
            step(2, "Sign in to the gateway")
            step(3, "Connect to the computer")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("connectionSteps")
    }

    private func step(_ index: Int, _ title: LocalizedStringKey, hint: LocalizedStringKey? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Group {
                if index < current {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if index == current {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 18)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(index == current ? .semibold : .regular)
                    .foregroundStyle(index < current ? .secondary : .primary)
                if index == current, let hint {
                    Text(hint)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .opacity(index > current ? 0.55 : 1)
        // The icons are hidden: VoiceOver hears the state.
        .accessibilityElement(children: .combine)
        .accessibilityValue(stepState(index))
    }

    private func stepState(_ index: Int) -> Text {
        if index < current { return Text("Done") }
        return index == current ? Text("In progress") : Text(verbatim: "")
    }
}

/// The app's picture: a remote desktop secured with a smart card (drawn, so it stays sharp and
/// follows the dark mode; the colors match the app icon).
struct AppIllustration: View {
    var width: CGFloat = 112
    @Environment(\.colorScheme) private var colorScheme

    private static let lightBlue = Color(red: 0.24, green: 0.53, blue: 0.97)
    private static let darkBlue = Color(red: 0.09, green: 0.28, blue: 0.71)
    private static let gold = Color(red: 0.91, green: 0.71, blue: 0.29)
    private static let goldLine = Color(red: 0.73, green: 0.53, blue: 0.16)
    private static let paleLine = Color(red: 0.84, green: 0.86, blue: 0.9)

    var body: some View {
        let dark = colorScheme == .dark
        Canvas { context, size in
            context.scaleBy(x: size.width / 132, y: size.height / 104)
            drawMonitor(in: context, dark: dark)
            // The smart card, slightly tilted in front of the monitor.
            var card = context
            card.translateBy(x: 104, y: 70)
            card.rotate(by: .degrees(-8))
            card.translateBy(x: -104, y: -70)
            drawCard(in: card, dark: dark)
        }
        .frame(width: width, height: width * 104 / 132)
        .accessibilityHidden(true)
    }

    private func drawMonitor(in context: GraphicsContext, dark: Bool) {
        let screen = Path(roundedRect: CGRect(x: 6, y: 6, width: 100, height: 68), cornerRadius: 10)
        let gradient = Gradient(colors: [Self.lightBlue, Self.darkBlue])
        context.fill(
            screen, with: .linearGradient(gradient, startPoint: CGPoint(x: 56, y: 6), endPoint: CGPoint(x: 56, y: 74)))
        let inner = Path(roundedRect: CGRect(x: 14, y: 14, width: 84, height: 52), cornerRadius: 5)
        context.fill(inner, with: .color(.white.opacity(0.14)))
        var stand = Path()
        stand.move(to: CGPoint(x: 44, y: 92))
        stand.addLine(to: CGPoint(x: 68, y: 92))
        stand.move(to: CGPoint(x: 56, y: 74))
        stand.addLine(to: CGPoint(x: 56, y: 92))
        let standColor = dark ? Color(red: 0.31, green: 0.5, blue: 0.88) : Self.darkBlue
        context.stroke(stand, with: .color(standColor), style: StrokeStyle(lineWidth: 6, lineCap: .round))
        // The lock on the screen.
        let lock = Path(roundedRect: CGRect(x: 49, y: 33, width: 14, height: 12), cornerRadius: 2.4)
        context.fill(lock, with: .color(.white))
        var shackle = Path()
        shackle.move(to: CGPoint(x: 52, y: 33))
        shackle.addLine(to: CGPoint(x: 52, y: 29.6))
        shackle.addArc(
            center: CGPoint(x: 56, y: 29.6), radius: 4, startAngle: .degrees(180), endAngle: .degrees(0),
            clockwise: false)
        shackle.addLine(to: CGPoint(x: 60, y: 33))
        context.stroke(shackle, with: .color(.white), lineWidth: 2.6)
    }

    private func drawCard(in context: GraphicsContext, dark: Bool) {
        let card = Path(roundedRect: CGRect(x: 78, y: 52, width: 48, height: 31), cornerRadius: 5)
        context.fill(card, with: .color(dark ? Color(white: 0.96) : .white))
        context.stroke(card, with: .color(dark ? Color(white: 0.36) : Self.paleLine), lineWidth: 1.2)
        context.fill(
            Path(roundedRect: CGRect(x: 84, y: 61, width: 12, height: 10), cornerRadius: 2), with: .color(Self.gold))
        var contacts = Path()
        contacts.move(to: CGPoint(x: 84, y: 66))
        contacts.addLine(to: CGPoint(x: 96, y: 66))
        contacts.move(to: CGPoint(x: 90, y: 61))
        contacts.addLine(to: CGPoint(x: 90, y: 71))
        context.stroke(contacts, with: .color(Self.goldLine), lineWidth: 0.9)
        let line1 = Path(roundedRect: CGRect(x: 101, y: 62, width: 19, height: 3), cornerRadius: 1.5)
        let line2 = Path(roundedRect: CGRect(x: 101, y: 68, width: 13, height: 3), cornerRadius: 1.5)
        context.fill(line1, with: .color(Self.paleLine))
        context.fill(line2, with: .color(Self.paleLine))
    }
}
