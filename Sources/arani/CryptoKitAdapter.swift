import Foundation
import CryptoKit

/// Provides E2E encryption/decryption and signing
public struct CryptoKitAdapter {
    public init() {}

    public func encrypt(_ plaintext: Data, using key: SymmetricKey) throws -> (ciphertext: Data, nonce: AES.GCM.Nonce, tag: Data) {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        return (sealed.ciphertext, sealed.nonce, sealed.tag)
    }

    public func decrypt(_ ciphertext: Data, nonce: AES.GCM.Nonce, tag: Data, using key: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        return try AES.GCM.open(sealed, using: key)
    }
}
