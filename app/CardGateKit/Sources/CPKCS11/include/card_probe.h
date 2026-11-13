#ifndef CARDGATE_CARD_PROBE_H
#define CARDGATE_CARD_PROBE_H

/// Result of looking at a PKCS#11 module without logging in.
typedef struct {
    /// PKCS#11 return value of the first failing call, 0 on success, -1 if the module cannot be loaded.
    long error;
    /// Slots with a token present.
    unsigned long tokens;
    /// PIN length limits and token flags (CKF_USER_PIN_*) of the first present token, or with
    /// `cg_card_probe_matching` of the token holding the matched certificate (`matched_token`).
    unsigned long pin_min_length;
    unsigned long pin_max_length;
    unsigned long token_flags;
    /// Token flags of all present tokens combined (bitwise or): with several tokens and none found
    /// to hold the sign-in certificate, a warning of any of them counts.
    unsigned long any_token_flags;
    /// With several tokens: 1 if the PIN fields above are of the token holding the certificate the
    /// `matches` callback of `cg_card_probe_matching` accepted, 0 if they are of the first token.
    int matched_token;
    /// Slot description of the first present token, trailing blanks removed. With common middleware
    /// it is the PC/SC reader name (at most 64 bytes, possibly cut off).
    char slot_description[65];
} cg_card_probe_result;

/// Loads the PKCS#11 module, reads which tokens are present and their token info, and unloads the
/// module. No session is opened (that alone takes seconds with some middleware).
cg_card_probe_result cg_card_probe(const char* module_path);

/// Called with the DER value of each certificate on a token; returns nonzero for the wanted one.
typedef int (*cg_certificate_matcher)(const unsigned char* der, unsigned long length, void* context);

/// Like `cg_card_probe`, but with several tokens the PIN fields are of the token holding the
/// certificate `matches` accepts (read in a session without logging in, which may take seconds).
cg_card_probe_result cg_card_probe_matching(const char* module_path, cg_certificate_matcher matches,
                                            void* context);

#endif
