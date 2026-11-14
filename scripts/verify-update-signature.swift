// Checks the EdDSA (Ed25519) signature of an update archive with a public key, as Sparkle does in the
// app before it installs an update.
//
// Usage: swift scripts/verify-update-signature.swift <file> <signature> <public key>   (base64)
// Exit status 0: valid, 1: invalid, 2: wrong arguments.
import CryptoKit
import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 4,
    let file = FileManager.default.contents(atPath: arguments[1]),
    let signature = Data(base64Encoded: arguments[2]),
    let keyData = Data(base64Encoded: arguments[3]),
    let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
else {
    FileHandle.standardError.write(Data("usage: verify-update-signature.swift <file> <signature> <public key>\n".utf8))
    exit(2)
}
exit(publicKey.isValidSignature(signature, for: file) ? 0 : 1)
