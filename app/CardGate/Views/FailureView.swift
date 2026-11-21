import CardGateKit
import SwiftUI

struct FailureView: View {
    @Environment(AppModel.self) private var model
    let failure: SessionFailure

    var body: some View {
        NoticeView(tone: failure.tone, systemImage: systemImage, title: Text(title), message: Text(advice)) {
            switch failure {
            case .computerCertificateChanged where model.canTrustNewComputerCertificate:
                Button("Trust the New Certificate") { model.trustNewComputerCertificate() }
                    .disabled(model.isBusy)
                    .padding(.top, 4)
                    .accessibilityIdentifier("failure.trustCertificate")
            case .computerOffersOnlyWeakerSecurity where model.securityWeakened:
                Button("Connect with Weaker Security") { model.connectWithWeakerSecurity() }
                    .disabled(model.isBusy)
                    .padding(.top, 4)
                    .accessibilityIdentifier("failure.weakerSecurity")
            case .securityRefused where model.requiresFailedNLA:
                Button("Try NLA Again") { model.tryNLAAgain() }
                    .disabled(model.isBusy)
                    .padding(.top, 4)
                    .accessibilityIdentifier("failure.tryNLA")
            default:
                EmptyView()
            }
        }
        .accessibilityIdentifier("failure")
    }

    private var systemImage: String {
        switch failure {
        case .untrustedCertificate, .gatewayCertificateNotPublic, .gatewayCertificateChanged,
            .computerCertificateChanged:
            "xmark.shield.fill"
        case .computerOffersOnlyWeakerSecurity: "exclamationmark.shield.fill"
        case .notAllowedOnComputer: "person.crop.circle.badge.xmark"
        case .gatewayUnreachable, .connectionLost: "wifi.exclamationmark"
        case .pinTimedOut, .idleTimeout: "clock.badge.exclamationmark"
        case .wrongPIN, .cardLocked, .cardRefusedLogin, .noCertificate, .multipleCertificates, .unsupportedCardKey:
            "creditcard.trianglebadge.exclamationmark"
        case .gatewayDenied, .computerUnreachable, .securityRefused, .kerberosFailed, .sessionTakenOver,
            .disconnectedByServer, .other:
            "exclamationmark.triangle.fill"
        }
    }

    private var title: LocalizedStringKey {
        switch failure {
        case .noCertificate: "No certificate found on the card"
        case .wrongPIN: "Wrong PIN"
        case .cardLocked: "The card is locked"
        case .cardRefusedLogin: "The card refused the sign-in"
        case .gatewayUnreachable: "The gateway cannot be reached"
        case .gatewayDenied: "The gateway refused the sign-in"
        case .untrustedCertificate: "The gateway's certificate is not trusted"
        case .gatewayCertificateNotPublic: "The gateway's certificate is not publicly trusted"
        case .multipleCertificates: "The card has several sign-in certificates"
        case .unsupportedCardKey: "The card's key type is not supported"
        case .gatewayCertificateChanged: "The gateway's certificate changed"
        case .pinTimedOut: "The PIN was not entered in time"
        case .computerUnreachable: "The computer cannot be reached"
        case .securityRefused: "The computer requires stronger connection security"
        case .computerOffersOnlyWeakerSecurity: "The computer offers only weaker connection security"
        case .computerCertificateChanged: "The computer's certificate changed"
        case .notAllowedOnComputer: "Your account may not connect to this computer"
        case .kerberosFailed: "Signing in to the computer with the card failed"
        case .connectionLost: "The connection was interrupted"
        case .sessionTakenOver: "Another connection took over the session"
        case .idleTimeout: "Disconnected after a period of inactivity"
        case .disconnectedByServer: "The computer ended the connection"
        case .other: "The connection failed"
        }
    }

    private var advice: LocalizedStringKey {
        switch failure {
        case .noCertificate:
            "Remove the card or token, insert it again and try once more."
        case .wrongPIN:
            "The PIN was not accepted. Be careful: after several wrong attempts the card gets locked."
        case .cardRefusedLogin:
            """
            The PIN may have been wrong, or the card or reader failed. Remove the card, insert it again \
            and connect once more. Be careful: after several wrong PINs the card gets locked.
            """
        case .cardLocked:
            "Too many wrong PINs were entered. Unlock the card with the PUK or contact your IT department."
        case .gatewayUnreachable:
            "Check your internet connection and the gateway address in the connection settings."
        case .gatewayDenied:
            "Your card is not allowed to use this gateway. Contact your IT department."
        case .untrustedCertificate:
            """
            The connection was stopped for your safety. Check the gateway address; if it is correct, \
            contact your IT department.
            """
        case .gatewayCertificateNotPublic:
            """
            CardGate accepts only certificates from public certification authorities. If your organization \
            uses its own certificate, contact your IT department. Otherwise the connection may be \
            intercepted: do not connect and report it to your IT department.
            """
        case .multipleCertificates:
            """
            Choose the certificate to sign in with: Edit Connection, section Advanced. If you do not know which \
            one, contact your IT department.
            """
        case .gatewayCertificateChanged:
            """
            For your safety the connection was not restored with the card. Connect again: CardGate \
            checks the new certificate first.
            """
        case .unsupportedCardKey:
            """
            CardGate can sign in to the gateway only with an RSA key; this card has another type (for \
            example ECC). Contact your IT department.
            """
        case .pinTimedOut:
            "The gateway does not wait long for the PIN. Click Connect and enter the PIN right away."
        case .computerUnreachable where model.computerMayRequireStrongerSecurity:
            """
            The gateway could not reach it. The computer may be turned off, or it now requires stronger \
            connection security: connect again, CardGate then tries it.
            """
        case .computerUnreachable:
            """
            The gateway could not reach it. Check the computer's name in the connection settings for a typo \
            and whether the computer is turned on. Contact your IT department if it persists.
            """
        case .securityRefused where model.requiresFailedNLA:
            """
            It requires network level authentication (NLA), and the sign-in with the card through the \
            gateway failed with it last time, so CardGate did not offer it. Contact your IT department \
            (NLA needs a gateway with a KDC proxy); try NLA again once it is fixed.
            """
        case .securityRefused where model.requiresNLAWithoutAnchor:
            """
            It requires network level authentication (NLA), and the certification authority that issued \
            your card could not be downloaded yet. Connect to your organization's network (or VPN) or the \
            internet and connect again.
            """
        case .securityRefused where model.session.computerRequires == .nla:
            """
            It requires network level authentication (NLA). Choose Security: Automatic (or NLA) in the \
            connection settings.
            """
        case .securityRefused where model.session.computerRequires == .tls:
            """
            It requires TLS, not RDP security. Choose Security: Automatic in the connection settings.
            """
        case .securityRefused:
            """
            It requires TLS or NLA. If Security is set to RDP Security, choose Automatic in the connection \
            settings.
            """
        case .computerOffersOnlyWeakerSecurity:
            if model.securityWeakened {
                """
                It used to accept stronger security than it offers now. If its administrator changed this \
                on purpose, connect with weaker security. Otherwise the connection may be intercepted: do not \
                connect and contact your IT department.
                """
            } else {
                """
                It accepts only weaker security than the one set for this connection. Choose Security: \
                Automatic in the connection settings.
                """
            }
        case .computerCertificateChanged:
            if let fingerprint = model.canTrustNewComputerCertificate
                ? model.session.changedCertificateFingerprint : nil
            {
                """
                It is not the certificate the computer had when you first connected, so the connection was \
                stopped for your safety. Trust the new certificate only if the computer's administrator \
                confirms it was renewed and its SHA-256 fingerprint is \(fingerprint); otherwise contact your \
                IT department.
                """
            } else {
                """
                It is not the certificate the computer had when you first connected, so the connection was \
                stopped for your safety. Trust the new certificate only if the computer's administrator \
                confirms it was renewed; otherwise contact your IT department.
                """
            }
        case .notAllowedOnComputer:
            """
            The computer verified your card, but your account is not allowed to connect to it remotely. \
            Ask the computer's administrator to add you to the Remote Desktop Users.
            """
        case .kerberosFailed:
            if model.connectsWithoutNLANextTime {
                """
                The computer chose network level authentication (NLA), and the sign-in with the card \
                through the gateway failed. Connect again: CardGate now connects without NLA. Details are \
                in the connection log.
                """
            } else {
                """
                The computer requires network level authentication (NLA), and the sign-in with the card \
                through the gateway failed. Details are in the connection log. Contact your IT department; \
                if the computer allows it, choose Security: TLS in the connection settings.
                """
            }
        case .connectionLost:
            "Check your internet connection and connect again."
        case .sessionTakenOver:
            "Someone signed in to the computer, or you connected to it from another device."
        case .idleTimeout:
            "The computer ends idle connections. Connect again to continue."
        case .disconnectedByServer:
            """
            An administrator or the computer itself disconnected you (for example before a restart). \
            Try again later or contact your IT department.
            """
        case .other(let code):
            "Details are in the connection log (\(code))."
        }
    }
}
