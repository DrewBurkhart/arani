import CloudKit
import CryptoKit
import Foundation

public struct DecryptedMessage {
    public let senderID: String
    public let text: String
    public let date: Date
}

@MainActor
public class ChatClient {
    let store: CloudKitMessagingStore
    let crypto: CryptoKitAdapter
    let keyManager: KeyManager
    let container: CKContainer

    public init(
        store: CloudKitMessagingStore =
            CloudKitStore(
                containerIdentifier: CKContainer.default().containerIdentifier!
            ),
        crypto: CryptoKitAdapter = CryptoKitAdapter(),
        keyManager: KeyManager = .shared,
        container: CKContainer = .default()
    ) {
        self.store = store
        self.crypto = crypto
        self.keyManager = keyManager
        self.container = container
    }

    public func startNewConversation(with users: [String]) async throws
        -> ConversationRecord
    {
        let threadKey = SymmetricKey(size: .bits256)

        var threadKeyBlobs: [String: Data] = [:]
        for userRecordName in users + [
            try await container.userRecordID().recordName
        ] {
            let publicKeyData = try await fetchPublicKey(for: userRecordName)
            let theirPubKey = try Curve25519.KeyAgreement.PublicKey(
                rawRepresentation: publicKeyData
            )

            let sealed = try ChaChaPoly.seal(
                threadKey.withUnsafeBytes { Data($0) },
                using: SymmetricKey(data: theirPubKey.rawRepresentation)
            )
            threadKeyBlobs[userRecordName] = sealed.combined
        }

        return try await store.createConversation(
            participants: Array(threadKeyBlobs.keys),
            threadKeyBlobs: threadKeyBlobs
        )
    }

    public func send(_ plaintext: String, in conversation: ConversationRecord) async throws {
        // TODO: encrypt and append message
    }

    public func messagesPublisher(for conversation: ConversationRecord) -> AsyncStream<DecryptedMessage> {
        // TODO: subscribe and decrypt messages
        return AsyncStream { _ in }
    }
}

extension ChatClient {
    /// Fetches the raw public-key bytes you previously published for `userRecordName`.
    func fetchPublicKey(for userRecordName: String) async throws -> Data {
        let profileRecordID = CKRecord.ID(recordName: userRecordName)
        let publicDB = container.publicCloudDatabase

        let record = try await publicDB.record(for: profileRecordID)

        guard let keyData = record["publicKey"] as? Data else {
            throw NSError(
                domain: "ChatClient",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No publicKey field on UserProfile"
                ]
            )
        }
        return keyData
    }
}
