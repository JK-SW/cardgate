#ifndef CARDGATE_CARD_PROBE_H
#define CARDGATE_CARD_PROBE_H

/// Result of looking at a PKCS#11 module without logging in or opening a session.
typedef struct {
    /// PKCS#11 return value of the first failing call, 0 on success, -1 if the module cannot be loaded.
    long error;
    /// Slots with a token present.
    unsigned long tokens;
    /// PIN length limits and token flags (CKF_USER_PIN_*) of the first present token.
    unsigned long pin_min_length;
    unsigned long pin_max_length;
    unsigned long token_flags;
    /// Slot description of the first present token, trailing blanks removed. With common middleware
    /// it is the PC/SC reader name (at most 64 bytes, possibly cut off).
    char slot_description[65];
} cg_card_probe_result;

/// Loads the PKCS#11 module, reads which tokens are present and the token info of the first one,
/// and unloads the module. No session is opened (that alone takes seconds with some middleware).
cg_card_probe_result cg_card_probe(const char* module_path);

#endif
