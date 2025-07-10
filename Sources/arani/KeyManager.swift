import Foundation
import CryptoKit
import Security

public enum KeychainError: Error {
    case unhandledError(status: OSStatus)
}

public class KeyManager {
    private let keyTag = "io.github.drewburkhart.arani.identityKey"
    @MainActor public static let shared = KeyManager()
    private init() {}

    /// Generates or retrieves existing X25519 key pair
    public func identityKeyPair() throws -> (
        privateKey: Curve25519.KeyAgreement.PrivateKey,
        publicKey: Data
    ) {
        let tagData = Data(keyTag.utf8)

        // Fetch existing private key data
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrAccount: keyTag,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let keyData = item as? Data {
            // Key data found, rehydrate the CryptoKit key
            let privateKey = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: keyData)
            return (privateKey, privateKey.publicKey.rawRepresentation)
        }

        // Key data not found, generate a new key and store it
        if status == errSecItemNotFound {
            let privateKey = Curve25519.KeyAgreement.PrivateKey()
            let raw = privateKey.rawRepresentation

            var addQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrAccount: keyTag,
                kSecValueData: raw
            ]

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledError(status: addStatus)
            }

            return (privateKey, privateKey.publicKey.rawRepresentation)
        }

        // Something else went wrong
        throw KeychainError.unhandledError(status: status)
    }
}
