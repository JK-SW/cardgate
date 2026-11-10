#ifndef CARDGATE_CARD_PROBE_H
#define CARDGATE_CARD_PROBE_H

/// Result of looking at a PKCS#11 module without logging in.
typedef struct {
    /// PKCS#11 return value of the first failing call, 0 on success, -1 if the module cannot be loaded.
    long error;
    /// Slots with a token present.
    unsigned long tokens;
    /// Certificate objects on all present tokens.
    unsigned long certificates;
    /// PIN length limits and token flags (CKF_USER_PIN_*) of the first token with certificates.
    unsigned long pin_min_length;
    unsigned long pin_max_length;
    unsigned long token_flags;
} cg_card_probe_result;

/// Loads the PKCS#11 module, counts present tokens and certificates (public objects, no PIN) and
/// unloads the module again.
cg_card_probe_result cg_card_probe(const char* module_path);

#endif
