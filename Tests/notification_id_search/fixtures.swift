import Foundation
import DGSimpleSettings

struct PeerId: Hashable { let namespace: Int; let value: Int64 }
struct MessageId: Hashable { let peerId: PeerId; let namespace: Int; let id: Int32 }
enum Namespaces {
    enum Peer { static let CloudUser = 0; static let SecretChat = 3 }
    enum Message { static let Cloud = 0; static let Local = 1 }
}
class Peer { let id: PeerId; init(_ id: PeerId) { self.id = id } }
enum TelegramPeerAccessHash { case personal(Int64); case genericPublic(Int64) }
final class TelegramUser: Peer {
    var botInfo: Bool?
    var isDeleted = false
    var accessHash: TelegramPeerAccessHash? = .personal(42)
}
struct EnginePeer { let id: PeerId }
struct FoundPeer { let peer: EnginePeer; let subscribers: Int32? }
struct LocalMessageTags: OptionSet {
    let rawValue: Int
    static let donutgramDeleted = Self(rawValue: 1)
    static let donutgramSavedViewOnce = Self(rawValue: 2)
}
struct StoreMessageFlags: OptionSet {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }
    init(_ other: Self) { self = other }
    static let Incoming = Self(rawValue: 1)
}
struct ForwardInfo { let authorId: PeerId }
struct StoreMessageForwardInfo {
    let authorId: PeerId
    init(_ value: ForwardInfo) { self.authorId = value.authorId }
}
enum StoreMessageId { case Id(MessageId); case Partial }
struct StoreMessage {
    let id: StoreMessageId
    let globallyUniqueId: Int64?
    let groupingKey: Int64?
    let threadId: Int64?
    let timestamp: Int32
    let flags: StoreMessageFlags
    let tags: Set<String>
    let globalTags: Set<String>
    let localTags: LocalMessageTags
    let forwardInfo: StoreMessageForwardInfo?
    let authorId: PeerId?
    let text: String
    let attributes: [String]
    let media: [String]
    init(id: MessageId, customStableId: UInt32?, globallyUniqueId: Int64?, groupingKey: Int64?, threadId: Int64?, timestamp: Int32, flags: StoreMessageFlags, tags: Set<String>, globalTags: Set<String>, localTags: LocalMessageTags, forwardInfo: StoreMessageForwardInfo?, authorId: PeerId?, text: String, attributes: [String], media: [String]) {
        self.id = .Id(id); self.globallyUniqueId = globallyUniqueId; self.groupingKey = groupingKey
        self.threadId = threadId; self.timestamp = timestamp; self.flags = flags
        self.tags = tags; self.globalTags = globalTags; self.localTags = localTags
        self.forwardInfo = forwardInfo; self.authorId = authorId; self.text = text
        self.attributes = attributes; self.media = media
    }
}
struct Message {
    let id: MessageId
    let globallyUniqueId: Int64?
    let groupingKey: Int64?
    let threadId: Int64?
    let timestamp: Int32
    let flags: StoreMessageFlags
    let tags: Set<String>
    let globalTags: Set<String>
    let localTags: LocalMessageTags
    let forwardInfo: ForwardInfo?
    let author: Peer?
    let text: String
    let attributes: [String]
    let media: [String]
    init(_ store: StoreMessage, author: Peer?) {
        guard case let .Id(id) = store.id else { fatalError("partial message") }
        self.id = id; self.globallyUniqueId = store.globallyUniqueId; self.groupingKey = store.groupingKey
        self.threadId = store.threadId; self.timestamp = store.timestamp; self.flags = store.flags
        self.tags = store.tags; self.globalTags = store.globalTags; self.localTags = store.localTags
        self.forwardInfo = store.forwardInfo.map { ForwardInfo(authorId: $0.authorId) }
        self.author = author; self.text = store.text; self.attributes = store.attributes; self.media = store.media
    }
}
enum MessageUpdate { case update(StoreMessage) }
final class Transaction {
    var peers: [PeerId: Peer] = [:]
    var messages: [MessageId: Message] = [:]
    var deleted: [MessageId] = []
    func getPeer(_ id: PeerId) -> Peer? { self.peers[id] }
    func getMessage(_ id: MessageId) -> Message? { self.messages[id] }
    func updateMessage(_ id: MessageId, update: (Message) -> MessageUpdate) {
        guard let previous = self.messages[id] else { fatalError("missing") }
        if case let .update(store) = update(previous) {
            self.messages[id] = Message(store, author: store.authorId.flatMap { self.peers[$0] })
        }
    }
}
final class MediaBox {}
func _internal_deleteMessages(transaction: Transaction, mediaBox: MediaBox, ids: [MessageId], deleteMedia: Bool) {
    for id in ids { transaction.messages.removeValue(forKey: id) }
    transaction.deleted.append(contentsOf: ids)
}

// PRODUCTION_HELPERS

var checks = 0
func expect(_ condition: @autoclosure () -> Bool, _ description: String) {
    checks += 1
    precondition(condition(), description)
}

let args = CommandLine.arguments
if args.count == 3 {
    let suite = args[2]
    let defaults = UserDefaults(suiteName: suite)!
    if args[1] == "write-settings" {
        defaults.removePersistentDomain(forName: suite)
        let settings = DGMessagePreservationSettings(sharedDefaults: defaults, legacyDefaults: .standard, migrateLegacyValues: false)
        settings.saveDeletedMessages = true
        settings.saveInBotChats = true
        settings.saveEditHistory = false
        settings.saveViewOnceMedia = true
    } else {
        let settings = DGMessagePreservationSettings(sharedDefaults: defaults, legacyDefaults: .standard, migrateLegacyValues: false)
        expect(settings.saveDeletedMessages && settings.saveInBotChats && settings.saveViewOnceMedia, "extension reads another process's preferences")
        expect(!settings.saveEditHistory, "disabled preferences persist")
        defaults.removePersistentDomain(forName: suite)
        print("Cross-process settings checks passed")
    }
    exit(0)
}

let prefix = "donutgram-tests-" + UUID().uuidString
let shared = UserDefaults(suiteName: prefix + "-shared")!
let legacy = UserDefaults(suiteName: prefix + "-legacy")!
defer {
    shared.removePersistentDomain(forName: prefix + "-shared")
    legacy.removePersistentDomain(forName: prefix + "-legacy")
}
legacy.set(true, forKey: "donutgram.spy.saveDeletedMessages")
legacy.set(true, forKey: "donutgram.spy.saveEditHistory")
legacy.set(false, forKey: "donutgram.spy.saveInBotChats")
legacy.set(false, forKey: "donutgram.spy.saveViewOnceMedia")
let beforeMigration = DGMessagePreservationSettings(sharedDefaults: shared, legacyDefaults: legacy, migrateLegacyValues: false)
expect(!beforeMigration.saveDeletedMessages, "extension must not use its own enabled legacy defaults")
let migrated = DGMessagePreservationSettings(sharedDefaults: shared, legacyDefaults: legacy, migrateLegacyValues: true)
expect(migrated.saveDeletedMessages && migrated.saveEditHistory, "main app migrates enabled preferences")
expect(!migrated.saveInBotChats && !migrated.saveViewOnceMedia, "migration preserves disabled preferences")
migrated.saveDeletedMessages = false
let reopened = DGMessagePreservationSettings(sharedDefaults: shared, legacyDefaults: legacy, migrateLegacyValues: true)
expect(!reopened.saveDeletedMessages, "relaunch must not replace shared setting with stale legacy value")

let activeSuite = prefix + "-active"
defer { UserDefaults.standard.removePersistentDomain(forName: activeSuite) }
DGSimpleSettings.shared.configureMessagePreservation(appGroupName: activeSuite, isMainApp: false)
DGSimpleSettings.shared.saveDeletedMessages = true
DGSimpleSettings.shared.saveInBotChats = false
expect(UserDefaults(suiteName: activeSuite)!.bool(forKey: "donutgram.spy.saveDeletedMessages"), "settings UI writes app-group preferences")

let alice = TelegramUser(PeerId(namespace: 0, value: 1234567890))
let bot = TelegramUser(PeerId(namespace: 0, value: 20)); bot.botInfo = true
let secret = Peer(PeerId(namespace: 3, value: 30))
let id = MessageId(peerId: alice.id, namespace: 0, id: 100)
func store(_ id: MessageId, flags: StoreMessageFlags = [.Incoming], tags: LocalMessageTags = []) -> StoreMessage {
    StoreMessage(id: id, customStableId: nil, globallyUniqueId: 7, groupingKey: 8, threadId: 9, timestamp: 123,
                 flags: flags, tags: ["text"], globalTags: ["global"], localTags: tags, forwardInfo: nil,
                 authorId: id.peerId, text: "🙂 full message, not a push preview", attributes: ["entities", "reply"], media: ["photo"])
}
let firstProcess = Transaction()
firstProcess.peers = [alice.id: alice, bot.id: bot, secret.id: secret]
firstProcess.messages[id] = Message(store(id), author: alice)
// The notification and the app operate on the same stored message; the fixture
// models reopening the transaction without retaining the original handler.
let reopenedTransaction = Transaction()
reopenedTransaction.peers = firstProcess.peers
reopenedTransaction.messages = firstProcess.messages
donutgramDeleteMessagesFromNotification(transaction: reopenedTransaction, mediaBox: MediaBox(), ids: [id])
let retained = reopenedTransaction.getMessage(id)!
expect(retained.localTags.contains(.donutgramDeleted), "delete push marks retained message")
expect(retained.text == firstProcess.messages[id]!.text, "full text survives deletion")
expect(retained.media == ["photo"] && retained.attributes == ["entities", "reply"], "media and entities survive deletion")
expect(retained.groupingKey == 8 && retained.threadId == 9 && retained.timestamp == 123, "album/topic/date survive deletion")
expect(reopenedTransaction.deleted.isEmpty, "retained record never reaches generic deletion")
donutgramDeleteMessagesFromNotification(transaction: reopenedTransaction, mediaBox: MediaBox(), ids: [id])
expect(reopenedTransaction.deleted.isEmpty, "duplicate delete push is idempotent")
let missing = MessageId(peerId: alice.id, namespace: 0, id: 101)
expect(!donutgramPreserveDeletedMessage(transaction: reopenedTransaction, messageId: missing), "missing text is not reconstructed")
let botId = MessageId(peerId: bot.id, namespace: 0, id: 102)
reopenedTransaction.messages[botId] = Message(store(botId), author: bot)
donutgramDeleteMessagesFromNotification(transaction: reopenedTransaction, mediaBox: MediaBox(), ids: [botId])
expect(reopenedTransaction.getMessage(botId) == nil, "disabled bot retention applies to extension")
DGSimpleSettings.shared.saveInBotChats = true
reopenedTransaction.messages[botId] = Message(store(botId), author: bot)
expect(donutgramPreserveDeletedMessage(transaction: reopenedTransaction, messageId: botId), "enabled bot retention applies")
let secretId = MessageId(peerId: secret.id, namespace: 0, id: 103)
reopenedTransaction.messages[secretId] = Message(store(secretId), author: secret)
expect(!donutgramPreserveDeletedMessage(transaction: reopenedTransaction, messageId: secretId), "secret chats excluded")
DGSimpleSettings.shared.saveDeletedMessages = false
reopenedTransaction.messages[id] = Message(store(id), author: alice)
donutgramDeleteMessagesFromNotification(transaction: reopenedTransaction, mediaBox: MediaBox(), ids: [id])
expect(reopenedTransaction.getMessage(id) == nil, "disabled retention follows normal deletion")
reopenedTransaction.messages[id] = Message(store(id, tags: [.donutgramSavedViewOnce]), author: alice)
expect(donutgramPreserveDeletedMessage(transaction: reopenedTransaction, messageId: id), "previously saved view-once copy stays retained")
let localId = MessageId(peerId: alice.id, namespace: 1, id: 104)
expect(!donutgramPreserveDeletedMessage(transaction: reopenedTransaction, messageId: localId), "local message ids excluded")
expect(donutgramIsNotificationMessage(store(id), expectedId: id), "matching incoming API message accepted")
expect(!donutgramIsNotificationMessage(store(missing), expectedId: id), "different message id rejected")
expect(!donutgramIsNotificationMessage(store(id, flags: []), expectedId: id), "outgoing reaction target rejected")

for (query, expected) in [("1234567890", Int64(1234567890)), (" 1234567890\n", 1234567890), ("000123", 123), ("72057594037927935", 0x00ffffffffffffff)] {
    expect(donutgramUserIdFromSearchQuery(query) == expected, "valid numeric user ID: \(query)")
}
for query in ["", " ", "0", "-100123", "+79991234567", "@123", "12 34", "12.0", "1e9", "١٢٣", "１２３", "9223372036854775808", "72057594037927936"] {
    expect(donutgramUserIdFromSearchQuery(query) == nil, "non-ID input rejected: \(query)")
}
let accountId = PeerId(namespace: 0, value: 999)
expect(donutgramCanOpenIdSearchUser(alice, accountPeerId: accountId), "known full user is openable")
alice.accessHash = .genericPublic(42)
expect(!donutgramCanOpenIdSearchUser(alice, accountPeerId: accountId), "min hash cannot open arbitrary chat")
alice.accessHash = nil
expect(!donutgramCanOpenIdSearchUser(alice, accountPeerId: accountId), "missing hash must not fabricate a result")
expect(donutgramCanOpenIdSearchUser(alice, accountPeerId: alice.id), "own account needs no access hash")
alice.isDeleted = true
expect(!donutgramCanOpenIdSearchUser(alice, accountPeerId: alice.id), "deleted users excluded")
let match = FoundPeer(peer: EnginePeer(id: alice.id), subscribers: nil)
let other = FoundPeer(peer: EnginePeer(id: bot.id), subscribers: nil)
let merged = donutgramAddingUserIdResult(match, to: ([other, match], [match, other]))
expect(merged.0.map { $0.peer.id } == [alice.id, bot.id], "ID match comes first with no duplicate")
expect(merged.1.map { $0.peer.id } == [bot.id], "ID result deduplicated across sections")
let unchanged = donutgramAddingUserIdResult(nil, to: ([other], [match]))
expect(unchanged.0.first?.peer.id == bot.id && unchanged.1.first?.peer.id == alice.id, "failed ID lookup preserves ordinary search")
print("Passed \(checks) production-helper and shared-settings regression checks")
