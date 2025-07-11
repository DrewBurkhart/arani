import CloudKit
import Foundation

public struct ConversationRecord: Identifiable {
    public let id: CKRecord.ID
    public let initiatorPublicKey: Data
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

@MainActor
public protocol CloudKitMessagingStore {
    func createConversation(
        participants: [String],
        threadKeyBlobs: [String: Data]
    ) async throws -> ConversationRecord
    func fetchConversations() async throws -> [ConversationRecord]
    func subscribe(
        to conversation: ConversationRecord,
        handler: @escaping (MessageRecord) -> Void
    ) -> CKQuerySubscription
    func appendMessage(
        _ message: MessageRecord,
        to conversation: ConversationRecord
    ) async throws
    func fetchMessages(in conversation: ConversationRecord) async throws
        -> [CKRecord]
}

@MainActor
public class CloudKitStore: CloudKitMessagingStore {
    let container: CKContainer
    let database: CKDatabase

    public init(containerIdentifier: String) {
        self.container = CKContainer(identifier: containerIdentifier)
        self.database = container.privateCloudDatabase
    }

    public func createConversation(
        participants: [String],
        threadKeyBlobs: [String: Data]
    ) async throws -> ConversationRecord {
        let convoRecord = CKRecord(recordType: "Conversation")

        let encoder = JSONEncoder()
        let dictForJSON = threadKeyBlobs.mapValues { $0.base64EncodedString() }
        let jsonData = try encoder.encode(dictForJSON)
        convoRecord["threadKeyBlobs"] = jsonData

        let (priv, pubData) = try KeyManager.shared.identityKeyPair()
        convoRecord["initiatorPublicKey"] = pubData as NSData

        let share = CKShare(rootRecord: convoRecord)
        share[CKShare.SystemFieldKey.title] = "Arani Chat"
        share.publicPermission = .none

        for userRecordName in participants {
            let recordID = CKRecord.ID(recordName: userRecordName)

            let participant = try await container.shareParticipant(
                forUserRecordID: recordID
            )
            participant.permission = .readWrite

            share.addParticipant(participant)
        }

        let (resultsByID, _) = try await database.modifyRecords(
            saving: [convoRecord, share],
            deleting: []
        )

        let savedCKRecords: [CKRecord] = try resultsByID.values.map { result in
            try result.get()
        }

        guard
            let rec = savedCKRecords.first(where: {
                $0.recordType == "Conversation"
            })
        else {
            throw NSError(
                domain: "CloudKitStore",
                code: 0,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Missing Conversation record in save"
                ]
            )
        }

        return ConversationRecord(
            id: rec.recordID,
            initiatorPublicKey: rec["initiatorPublicKey"] as! Data,
            encryptedThreadKeys: threadKeyBlobs
        )
    }

    public func fetchConversations() async throws -> [ConversationRecord] {
        let query = CKQuery(
            recordType: "Conversation",
            predicate: NSPredicate(value: true)
        )

        let (privateMatchesArray, _) = try await database.records(
            matching: query
        )
        let (sharedMatchesArray, _) = try await container.sharedCloudDatabase
            .records(matching: query)

        let privateMatches = Dictionary(
            uniqueKeysWithValues: privateMatchesArray
        )
        let sharedMatches = Dictionary(uniqueKeysWithValues: sharedMatchesArray)

        // Merge, preferring private on key collisions
        let allMatches = privateMatches.merging(sharedMatches) {
            privateResult,
            _ in privateResult
        }

        var conversations: [ConversationRecord] = []
        let decoder = JSONDecoder()

        for (_, result) in allMatches {
            let ckRecord = try result.get()
            guard let jsonData = ckRecord["threadKeyBlobs"] as? Data else {
                continue
            }
            let base64Map = try decoder.decode(
                [String: String].self,
                from: jsonData
            )
            let threadKeyBlobs = base64Map.compactMapValues {
                Data(base64Encoded: $0)
            }
            let initiator = ckRecord["initiatorPublicKey"] as! Data

            conversations.append(
                ConversationRecord(
                    id: ckRecord.recordID,
                    initiatorPublicKey: initiator,
                    encryptedThreadKeys: threadKeyBlobs
                )
            )
        }

        return conversations
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

    public func fetchMessages(in conversation: ConversationRecord) async throws
        -> [CKRecord]
    {
        let predicate = NSPredicate(
            format: "parent == %@",
            CKRecord.Reference(recordID: conversation.id, action: .none)
        )
        let query = CKQuery(recordType: "Message", predicate: predicate)

        let (matches, _) = try await database.records(matching: query)

        return try matches.map { pair in
            try pair.1.get()
        }
    }
}
