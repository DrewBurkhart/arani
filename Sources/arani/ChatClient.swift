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

    /// Creates a new ConversationRecord.
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

    /// Appends a MessageRecord to the Conversation.
    public func send(
        _ plaintext: String,
        in conversation: ConversationRecord
    ) async throws {
        let (myPrivKey, _) = try keyManager.identityKeyPair()

        let myRecordName = try await container.userRecordID().recordName

        guard let myBlob = conversation.encryptedThreadKeys[myRecordName] else {
            throw NSError(
                domain: "ChatClient",
                code: 0,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "No thread-key blob for this user"
                ]
            )
        }

        let threadKeyData = try AsymmetricCryptoKitAdapter()
            .decryptThreadKey(
                myBlob,
                initiatorPublicKeyData: conversation.initiatorPublicKey,
                myPrivateKey: myPrivKey
            )

        let threadKey = SymmetricKey(data: threadKeyData)

        let (ciphertext, nonce, tag) = try crypto.encrypt(
            Data(plaintext.utf8),
            using: threadKey
        )

        let message = MessageRecord(
            id: CKRecord.ID(recordName: UUID().uuidString),
            parent: CKRecord.Reference(
                record: CKRecord(
                    recordType: "Conversation",
                    recordID: conversation.id
                ),
                action: .none
            ),
            ciphertext: ciphertext,
            nonce: Data(nonce),
            tag: tag,
            senderID: try await container.userRecordID().recordName,
            timestamp: Date(),
            signature: nil
        )

        try await store.appendMessage(message, to: conversation)
    }

    /// Call this when you receive a new Message CKRecord.
    /// - Parameters:
    ///   - record:       The raw CKRecord of type "Message".
    ///   - conversation: The conversation it belongs to (to get the thread key).
    ///   - handler:      Your UI callback with a decrypted message.
    func handleIncoming(
        _ record: CKRecord,
        in conversation: ConversationRecord,
        handler: @escaping (DecryptedMessage) -> Void
    ) {
        Task {
            do {
                let ciphertext = record["ciphertext"] as! Data
                let nonceData = record["nonce"] as! Data
                let tagData = record["tag"] as! Data
                let senderID = record["senderID"] as! String
                let timestamp = record["timestamp"] as! Date

                let myRecordName = try await container.userRecordID().recordName
                guard
                    let myBlob = conversation.encryptedThreadKeys[myRecordName]
                else {
                    throw NSError(
                        domain: "ChatClient",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "No thread key for current user"
                        ]
                    )
                }

                let (myPrivKey, _) = try keyManager.identityKeyPair()
                let threadKeyData = try AsymmetricCryptoKitAdapter()
                    .decryptThreadKey(
                        myBlob,
                        initiatorPublicKeyData: conversation.initiatorPublicKey,
                        myPrivateKey: myPrivKey
                    )
                let threadKey = SymmetricKey(data: threadKeyData)

                let nonce = try AES.GCM.Nonce(data: nonceData)
                let plain = try crypto.decrypt(
                    ciphertext,
                    nonce: nonce,
                    tag: tagData,
                    using: threadKey
                )
                let text = String(decoding: plain, as: UTF8.self)

                let msg = DecryptedMessage(
                    senderID: senderID,
                    text: text,
                    date: timestamp
                )
                handler(msg)

            } catch {
                print("Failed to handle incoming message:", error)
            }
        }
    }

    public func messagesPublisher(for conversation: ConversationRecord) -> AsyncStream<DecryptedMessage> {
        // TODO: subscribe and decrypt messages
        return AsyncStream { _ in }

    /// Decrypt one MessageRecord into DecryptedMessage
    // TODO: This should probably move to a crypto module.
    private func decrypt(
        _ message: MessageRecord,
        in conversation: ConversationRecord
    ) async throws -> DecryptedMessage {
        let ciphertext = message.ciphertext
        let nonce = try AES.GCM.Nonce(data: message.nonce)
        let tag = message.tag
        let senderID = message.senderID
        let timestamp = message.timestamp

        let myID = try await container.userRecordID().recordName
        guard let blob = conversation.encryptedThreadKeys[myID] else {
            throw NSError(
                domain: "ChatClient",
                code: 0,
                userInfo: [
                    NSLocalizedDescriptionKey: "No thread key for current user"
                ]
            )
        }
        let (priv, _) = try keyManager.identityKeyPair()
        let keyData = try AsymmetricCryptoKitAdapter()
            .decryptThreadKey(
                blob,
                initiatorPublicKeyData: conversation.initiatorPublicKey,
                myPrivateKey: priv
            )
        let threadKey = SymmetricKey(data: keyData)

        let plain = try crypto.decrypt(
            ciphertext,
            nonce: nonce,
            tag: tag,
            using: threadKey
        )
        let text = String(decoding: plain, as: UTF8.self)

        return DecryptedMessage(senderID: senderID, text: text, date: timestamp)
    }

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
