import CardGateKit
import CryptoKit
import Foundation
import Testing

struct BytesTests {
    @Test func hexOfBytesAndDigests() {
        #expect([0x00, 0x0f, 0xab].lowercaseHex == "000fab")
        #expect(Insecure.SHA1.hash(data: Data("abc".utf8)).lowercaseHex == "a9993e364706816aba3e25717850c26c9cd0d89d")
    }

    /// The writing end is still open (as in a child process of the writer): no waiting for the end.
    @Test func readsAPipeWithoutWaitingForItsEnd() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data("0 1\n".utf8))
        #expect(pipe.fileHandleForReading.readAvailableWithoutWaiting() == Data("0 1\n".utf8))
        #expect(pipe.fileHandleForReading.readAvailableWithoutWaiting().isEmpty)
        try pipe.fileHandleForWriting.close()
    }
}
