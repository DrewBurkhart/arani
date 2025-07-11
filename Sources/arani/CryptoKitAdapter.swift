import CryptoKit
import Foundation

/// Provides E2E encryption/decryption and signing
public struct CryptoKitAdapter {
    public init() {}

    public func encrypt(_ plaintext: Data, using key: SymmetricKey) throws -> (
        ciphertext: Data, nonce: AES.GCM.Nonce, tag: Data
    ) {
        let sealed = try AES.GCM.seal(plaintext, using: key)
        return (sealed.ciphertext, sealed.nonce, sealed.tag)
    }

    public func decrypt(
        _ ciphertext: Data,
        nonce: AES.GCM.Nonce,
        tag: Data,
        using key: SymmetricKey
    ) throws -> Data {
        let sealed = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )
        return try AES.GCM.open(sealed, using: key)
    }
}

public struct AsymmetricCryptoKitAdapter {
    public init() {}

    /// Decrypts the per-user thread-key blob.
    public func decryptThreadKey(
        _ blob: Data,
        initiatorPublicKeyData: Data,
        myPrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) throws -> Data {
        let initiatorPub = try Curve25519.KeyAgreement.PublicKey(
            rawRepresentation: initiatorPublicKeyData
        )

        // ECDH
        let sharedSecret = try myPrivateKey.sharedSecretFromKeyAgreement(
            with: initiatorPub
        )

        // Derive symmetric key
        let symm = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("arani-thread-key".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )

        // Open the sealed box
        let box = try AES.GCM.SealedBox(combined: blob)
        return try AES.GCM.open(box, using: symm)
    }
}
