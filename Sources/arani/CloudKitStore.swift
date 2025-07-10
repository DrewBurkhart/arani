import CloudKit
import Foundation

public struct ConversationRecord: Identifiable {
    public let id: CKRecord.ID
    public var encryptedThreadKeys: [String: Data]
}

public struct MessageRecord: Identifiable {
    public let id: CKRecord.ID
    public let parent: CKRecord.Reference
    public let ciphertext: Data
    public let nonce: Data
    public let tag: Data
    public let senderID: String
    public let timestamp: Date
    public let signature: Data?
}

public protocol CloudKitMessagingStore {
    func createConversation(participants: [String], threadKeyBlobs: [String: Data]) async throws -> ConversationRecord
    func fetchConversations() async throws -> [ConversationRecord]
    func subscribe(
        to conversation: ConversationRecord,
        handler: @escaping (MessageRecord) -> Void
    ) -> CKQuerySubscription
    func appendMessage(
        _ message: MessageRecord,
        to conversation: ConversationRecord
    ) async throws
}

public class CloudKitStore: CloudKitMessagingStore {
    let container: CKContainer
    let database: CKDatabase

    public init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
    }

    public func createConversation(participants: [String], threadKeyBlobs: [String : Data]) async throws -> ConversationRecord {
        // TODO: implement creating and sharing Conversation record
        throw NSError(domain: "NotImplemented", code: 0)
    }

    public func fetchConversations() async throws -> [ConversationRecord] {
        // TODO: implement fetching conversations
        return []
    }

    public func subscribe(
        to conversation: ConversationRecord,
        handler: @escaping (MessageRecord) -> Void
    ) -> CKQuerySubscription {
        // Predicate that only matches messages in this conversation
        let predicate = NSPredicate(
            format: "parent == %@",
            CKRecord.Reference(recordID: conversation.id, action: .none)
        )

        let subscriptionID = "messages-\(conversation.id.recordName)"
        let subscription = CKQuerySubscription(
            recordType: "Message",
            predicate: predicate,
            subscriptionID: subscriptionID,
            options: .firesOnRecordCreation
        )

        // Tell CloudKit to send silent pushes for new records
        let info = CKSubscription.NotificationInfo()
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        Task.detached(priority: .background) { [db = database, subscription] in
            do {
                _ = try await db.save(subscription)
            } catch {
                print("Failed to save subscription:", error)
            }
        }

        return subscription
    }

    public func appendMessage(
        _ message: MessageRecord,
        to conversation: ConversationRecord
    ) async throws {
        let recordID = CKRecord.ID(
            recordName: message.id.recordName,
            zoneID: conversation.id.zoneID
        )
        let ckRecord = CKRecord(recordType: "Message", recordID: recordID)

        ckRecord["parent"] = message.parent
        ckRecord["ciphertext"] = message.ciphertext as NSData
        ckRecord["nonce"] = message.nonce as NSData
        ckRecord["tag"] = message.tag as NSData
        ckRecord["senderID"] = message.senderID as NSString
        ckRecord["timestamp"] = message.timestamp as NSDate
        if let signature = message.signature {
            ckRecord["signature"] = signature as NSData
        }

        _ = try await database.modifyRecords(
            saving: [ckRecord],
            deleting: []
        )
    }
}

    }
}
