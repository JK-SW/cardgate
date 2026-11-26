import Foundation

/// The texts of the client log the log window's view depends on (the parser's are in `SessionLogTexts`).
extension ConnectionLog {
    /// The client tells Windows the card was taken out of the redirected reader; Windows handles it
    /// and the app lists the removal. Other errors of the redirected reader are problems.
    static func isCardRemovedAnswer(_ line: String) -> Bool {
        line.contains(redirectedReaderAnswer) && cardRemovedCodes.contains(where: line.contains)
    }

    static let redirectedReaderAnswer = "[com.freerdp.utils.smartcard.call] - [scard_log_status_error_wlog]"

    static let cardRemovedCodes = ["SCARD_W_REMOVED_CARD", "SCARD_E_NO_SMARTCARD", "SCARD_W_RESET_CARD"]

    /// Answers that the reader is gone: harmless only while the card is out (`cardInReader`). A token
    /// is a reader of its own – pulling the only one, macOS answers "no service" until it is back –
    /// and an operation the removal interrupted gets "reader unavailable". Otherwise they are problems.
    static func isReaderGoneAnswer(_ line: String) -> Bool {
        line.contains(redirectedReaderAnswer) && readerGoneCodes.contains(where: line.contains)
    }

    static let readerGoneCodes = ["SCARD_E_NO_SERVICE", "SCARD_E_READER_UNAVAILABLE", "SCARD_E_UNKNOWN_READER"]

    /// Texts of the client log this view depends on (the parser's are in `SessionLogParser.logMarkers`).
    /// Format strings appear as written in the source ("%s").
    public static let logMarkers = [
        "This build does not support AAD security",
        "warn_credential_args",
        "Implement neon optimized version",
        "pthread_setschedprio",
        "krb5_get_etype_info",
        "QueryContextAttributes implement ulAttribute=",
        "SEC_E_UNSUPPORTED_FUNCTION",
        "No synthesizer for format",
        "ending it and resetting the card like Windows does",
        "scard_log_status_error_wlog",
        "Failed to connect",
        "Error: protocol security negotiation or connection failure",
        "%s returned an error: %s",
        "Unsupported BIO_CTRL",
        "winpr_log_backtrace_ex",
        "no certificates found",
        "E_PROXY_SESSIONTIMEOUT",
        "E_PROXY_REAUTH_",
        "audio output failed, dropping sound until the device is closed: %s",
        "Failed to start audio player",
        "Connection aborted by user",
        "Unhandled SSL error",
        "%s retries exceeded",
        "DisconnectProviderUltimatum",
        "CHANNEL_RC_BAD_CHANNEL_HANDLE",
        "Certificate verification failure",
        "disconnect %s by the user",
        "signed in: releasing the modifier keys",
        "confirmed by its fingerprint, replacing the stored one",
        "verified by Kerberos, replacing the stored one",
        "Terminate with",
    ]
}
