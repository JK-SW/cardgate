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
        case .notAllowedOnComputer, .accountDisabled, .accountLockedOut, .accountExpired, .accountRestricted,
            .accountUnknownToDomain, .accountRevoked:
            "person.crop.circle.badge.xmark"
        case .domainNotTrusted: "xmark.shield.fill"
        case .clockSkew: "clock.badge.exclamationmark"
        case .cardCertificateRejected: "creditcard.trianglebadge.exclamationmark"
        case .gatewayUnreachable, .connectionLost: "wifi.exclamationmark"
        case .pinTimedOut, .idleTimeout: "clock.badge.exclamationmark"
        case .wrongPIN, .cardLocked, .cardRefusedLogin, .noCertificate, .multipleCertificates, .unsupportedCardKey:
            "creditcard.trianglebadge.exclamationmark"
        case .gatewayDenied, .computerUnreachable, .securityRefused, .kerberosFailed, .sessionTakenOver,
            .disconnectedByServer, .clientCrashed, .other, .domainUnreachable, .computerUnknownToDomain,
            .computerNotAllowedByGateway, .gatewayTemporarilyUnavailable, .gatewayNoSmartCard, .computerRefused,
            .noLicense, .windowsFailed:
            "exclamationmark.triangle.fill"
        }
    }

    private var title: String { failure.title }

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
        case .kerberosFailed, .domainUnreachable, .domainNotTrusted:
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
        case .clockSkew where model.connectsWithoutNLANextTime:
            """
            Check the date and time in System Settings → General → Date & Time. Connect again: CardGate now \
            connects without NLA.
            """
        case .clockSkew:
            "Check the date and time in System Settings → General → Date & Time, then connect again."
        case .computerUnknownToDomain where model.connectsWithoutNLANextTime:
            """
            Check that the connection settings have the computer's full name with its domain (for example \
            pc01.example.com). Connect again: CardGate now connects without NLA.
            """
        case .computerUnknownToDomain:
            "Enter the computer's full name with its domain (for example pc01.example.com) in the connection settings."
        case .accountUnknownToDomain where model.connectsWithoutNLANextTime:
            "Connect again: CardGate now connects without NLA. If it fails, contact your IT department."
        case .accountUnknownToDomain, .accountRevoked, .accountDisabled, .accountLockedOut, .accountExpired,
            .computerRefused, .noLicense:
            "Contact your IT department."
        case .accountRestricted:
            "Your account has a restriction, for example its sign-in hours. Contact your IT department."
        case .cardCertificateRejected:
            "The certificate may be invalid or revoked. Contact your IT department."
        case .computerNotAllowedByGateway:
            """
            Check the computer's full name in the connection settings (for example pc01.example.com). If it is \
            correct, contact your IT department.
            """
        case .gatewayTemporarilyUnavailable:
            "Try again in a while."
        case .gatewayNoSmartCard:
            "Check the gateway address in the connection settings. If it is correct, contact your IT department."
        case .windowsFailed:
            "Connect again. If it happens again, contact your IT department."
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
        case .clientCrashed(SIGKILL):
            "Connect again."
        case .clientCrashed:
            """
            This is an error in the program. Connect again. If it happens again, please report it and attach \
            the connection log.
            """
        case .other(let code):
            "Details are in the connection log (\(code))."
        }
    }
}

extension SessionFailure {
    /// The title of the failure, also the connection log's message for it.
    var title: String {
        switch self {
        case .noCertificate: String(localized: "No certificate found on the card")
        case .wrongPIN: String(localized: "Wrong PIN")
        case .cardLocked: String(localized: "The card is locked")
        case .cardRefusedLogin: String(localized: "The card refused the sign-in")
        case .gatewayUnreachable: String(localized: "The gateway cannot be reached")
        case .gatewayDenied: String(localized: "The gateway refused the sign-in")
        case .untrustedCertificate: String(localized: "The gateway's certificate is not trusted")
        case .gatewayCertificateNotPublic: String(localized: "The gateway's certificate is not publicly trusted")
        case .multipleCertificates: String(localized: "The card has several sign-in certificates")
        case .unsupportedCardKey: String(localized: "The card's key type is not supported")
        case .gatewayCertificateChanged: String(localized: "The gateway's certificate changed")
        case .pinTimedOut: String(localized: "The PIN was not entered in time")
        case .computerUnreachable: String(localized: "The computer cannot be reached")
        case .securityRefused: String(localized: "The computer requires stronger connection security")
        case .computerOffersOnlyWeakerSecurity: String(localized: "The computer offers only weaker connection security")
        case .computerCertificateChanged: String(localized: "The computer's certificate changed")
        case .notAllowedOnComputer: String(localized: "Your account may not connect to this computer")
        case .kerberosFailed: String(localized: "Signing in to the computer with the card failed")
        case .clockSkew: String(localized: "This Mac's time differs from the domain's")
        case .domainUnreachable: String(localized: "The domain could not be reached through the gateway")
        case .computerUnknownToDomain: String(localized: "The domain does not know this computer")
        case .accountUnknownToDomain: String(localized: "The domain does not know the card's account")
        case .accountRevoked: String(localized: "Your account is disabled or locked")
        case .domainNotTrusted: String(localized: "This Mac does not trust the domain's certificate")
        case .cardCertificateRejected: String(localized: "The domain refused the card's certificate")
        case .accountDisabled: String(localized: "Your account is disabled")
        case .accountLockedOut: String(localized: "Your account is locked")
        case .accountExpired: String(localized: "Your account has expired")
        case .accountRestricted: String(localized: "Your account cannot sign in now")
        case .computerNotAllowedByGateway: String(localized: "The gateway does not allow connecting to this computer")
        case .gatewayTemporarilyUnavailable: String(localized: "The gateway is temporarily unavailable")
        case .gatewayNoSmartCard: String(localized: "The gateway does not support signing in with a card")
        case .computerRefused: String(localized: "The computer refused the connection")
        case .noLicense: String(localized: "The computer has no remote desktop license")
        case .windowsFailed: String(localized: "An error in Windows ended the session")
        case .connectionLost: String(localized: "The connection was interrupted")
        case .sessionTakenOver: String(localized: "Another connection took over the session")
        case .idleTimeout: String(localized: "Disconnected after a period of inactivity")
        case .disconnectedByServer: String(localized: "The computer ended the connection")
        case .clientCrashed(SIGKILL): String(localized: "The system ended the remote desktop program")
        case .clientCrashed: String(localized: "The remote desktop program quit unexpectedly")
        case .other: String(localized: "The connection failed")
        }
    }
}
