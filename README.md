# arani

A Swift Package that layers end-to-end encrypted, CloudKit-backed messaging on top of CryptoKit and CKShare.

## Features

- **Append-only chat logs**: each message is an immutable `CKRecord`
- **Per-thread symmetric keys** securely exchanged via public-key encryption
- **Automatic sync & sharing** with CloudKit’s private & shared databases
- **Silent-push subscriptions** for new‑message notifications
- **Pure Swift concurrency (async/await)** APIs

## Getting Started

### 1. Add the Package

In Xcode, choose **File → Add Packages**, and point to:

```
https://github.com/drewburkhart/arani.git
```

Select version **1.0.0** and add the `arani` library to your app target.

### 2. Enable Capabilities

In your app target’s **Signing & Capabilities**:

1. **iCloud**
   - Check **CloudKit** and select your container.
2. **Push Notifications**
3. **Background Modes**
   - Enable **Remote notifications**.

### 3. Model Your CloudKit Schema

In CloudKit Dashboard, in the same container, add:

- **Record Type: `UserProfile`**
  - Record ID: user’s `CKContainer.default().userRecordID().recordName`
  - Field: `publicKey` (Data)

- **Record Type: `Conversation`**
  - Field: `threadKeyBlobs` (Data)

- **Record Type: `Message`**
  - Fields:
    - `parent` (Reference → Conversation)
    - `ciphertext` (Data)
    - `nonce` (Data)
    - `tag` (Data)
    - `senderID` (String)
    - `timestamp` (Date)
    - `signature` (Data, optional)

Make sure to **deploy** your schema changes.

### 4. Publish Your Public Key

In your `AppDelegate` or SwiftUI `App` init, call:

```swift
Task {
  try await KeyManager.shared.publishPublicKey()
}
```

This writes your `Curve25519` public key into the **public** database under your iCloud record name.

### 5. Use the AranitClient API

```swift
import arani

@MainActor
class ChatViewModel: ObservableObject {
  let client = AranitClient.shared

  @Published var conversations: [ConversationRecord] = []

  func loadConversations() async {
    conversations = try await client.fetchConversations()
  }

  func startChat(with participants: [String]) async {
    let convo = try await client.startNewConversation(with: participants)
    conversations.append(convo)
    subscribe(to: convo)
  }

  func subscribe(to convo: ConversationRecord) {
    // Legacy callback style:
    client.subscribe(to: convo) { message in
      // decrypt & display message if needed
    }

    // OR Swift-concurrency style:
    Task {
      for await message in client.messagesPublisher(for: convo) {
        // display DecryptedMessage
      }
    }
  }

  func send(_ text: String, in convo: ConversationRecord) async {
    try await client.send(text, in: convo)
  }
}
```

### 6. Handle Remote Notifications

In your `AppDelegate` (or SwiftUI adaptor), forward CloudKit pushes into the client::

```swift
func application(
  _ application: UIApplication,
  didReceiveRemoteNotification userInfo: [AnyHashable:Any],
  fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void
) {
  AraniClient.shared.handleRemoteNotification(userInfo, completion: completion)
}
```

(This calls your subscription handler and decrypts incoming messages.)

## License

`arani` is released under the MIT License. See [LICENSE](LICENSE) for details.
