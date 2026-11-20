/// SHA-256 fingerprint of a computer certificate as FreeRDP writes it (`ab:cd:…`, patch 0016).
public enum CertificateFingerprint {
    /// 32 bytes in lower case hex, separated by colons.
    public static func isValid(_ text: String) -> Bool {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 32
            && parts.allSatisfy { $0.count == 2 && $0.allSatisfy { "0123456789abcdef".contains($0) } }
    }
}
