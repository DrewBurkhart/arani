import Foundation
import CryptoKit
import CloudKit

/// Manages identity key pair for E2EE messaging
public class KeyManager {
    private let keyTag = "io.github.drewburkhart.arani.identityKey"
    @MainActor public static let shared = KeyManager()

    private init() {}

    /// Generates or retrieves existing X25519 key pair
    public func identityKeyPair() throws -> (privateKey: Curve25519.KeyAgreement.PrivateKey, publicKey: Data) {
        // TODO: implement keychain storage & retrieval
        let privateKey = Curve25519.KeyAgreement.PrivateKey()
        let publicKey = privateKey.publicKey.rawRepresentation
        return (privateKey, publicKey)
    }
}
