import Foundation
import CryptoKit
import CloudKit

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

    public init(store: CloudKitMessagingStore = CloudKitStore(containerIdentifier: CKContainer.default().containerIdentifier!),
                crypto: CryptoKitAdapter = CryptoKitAdapter(),
                keyManager: KeyManager = .shared) {
        self.store = store
        self.crypto = crypto
        self.keyManager = keyManager
    }

    public func startNewConversation(with users: [String]) async throws -> ConversationRecord {
        // TODO: implement thread key generation & conversation creation
        throw NSError(domain: "NotImplemented", code: 0)
    }

    public func send(_ plaintext: String, in conversation: ConversationRecord) async throws {
        // TODO: encrypt and append message
    }

    public func messagesPublisher(for conversation: ConversationRecord) -> AsyncStream<DecryptedMessage> {
        // TODO: subscribe and decrypt messages
        return AsyncStream { _ in }
    }
}
