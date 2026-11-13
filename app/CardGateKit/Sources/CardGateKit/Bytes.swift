public import Foundation

extension Sequence<UInt8> {
    /// Lowercase hex form, as used for certificate and file fingerprints (`FREERDP_SMARTCARD_CERT_SHA1`,
    /// approved modules).
    public var lowercaseHex: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

extension FileHandle {
    /// Reads what is in the pipe now, without waiting for its end: a process the writer started may
    /// keep the pipe open after the writer itself ended.
    public func readAvailableWithoutWaiting() -> Data {
        let descriptor = fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        defer { _ = fcntl(descriptor, F_SETFL, flags) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(descriptor, &buffer, buffer.count)
            if count > 0 {
                data.append(contentsOf: buffer[0..<count])
            } else if count < 0, errno == EINTR {
                continue  // interrupted by a signal: nothing lost, read again
            } else {
                break  // end, nothing more now (EAGAIN) or an error
            }
        }
        return data
    }
}
