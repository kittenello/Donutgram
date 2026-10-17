public struct PeerId: Hashable {
    let value: Int64
    func toInt64() -> Int64 { value }
}
public protocol Peer { var id: PeerId { get } }
enum Membership { case Member, Removed, Left }
enum Participation { case member, left, kicked }
struct GroupFlags: OptionSet {
    let rawValue: Int
    static let deactivated = GroupFlags(rawValue: 1)
}
struct TelegramGroup: Peer {
    let id: PeerId
    var membership: Membership
    var flags: GroupFlags = []
}
struct TelegramChannel: Peer {
    let id: PeerId
    var participationStatus: Participation
    var linkedCommunityId: PeerId? = nil
}
struct TelegramCommunity: Peer {
    let id: PeerId
    var participationStatus: Participation = .member
    var collapsedInDialogs: Bool? = true
}
enum PeerChatListInclusion: Equatable {
    case notIncluded
    case included(group: String, pin: Int)
}
enum Namespaces {
    enum Message { static let Cloud: Int32 = 0 }
    enum CachedItemCollection { static let donutgramBannedChats: Int8 = 123 }
}
final class DGSimpleSettings {
    static let shared = DGSimpleSettings()
    var keepBannedChats = false
}
final class ValueBoxKey {
    var value: Int64 = 0
    init(length: Int) {}
    func setInt64(_ offset: Int, value: Int64) { self.value = value }
}
struct ItemCacheEntryId: Hashable {
    let collectionId: Int8
    let value: Int64
    init(collectionId: Int8, key: ValueBoxKey) {
        self.collectionId = collectionId
        self.value = key.value
    }
}
struct CodableEntry {
    let data: Data
    init?<T: Encodable>(_ value: T) {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        self.data = data
    }
    func get<T: Decodable>(_ type: T.Type) -> T? { try? JSONDecoder().decode(type, from: data) }
}
enum HoleSpace { case everywhere }
final class Transaction {
    var peers: [PeerId: Peer] = [:]
    var inclusions: [PeerId: PeerChatListInclusion] = [:]
    var cache: [ItemCacheEntryId: CodableEntry] = [:]
    var holes: Set<String> = []
    func getPeer(_ id: PeerId) -> Peer? { peers[id] }
    func getPeerChatListInclusion(_ id: PeerId) -> PeerChatListInclusion { inclusions[id] ?? .notIncluded }
    func retrieveItemCacheEntry(id: ItemCacheEntryId) -> CodableEntry? { cache[id] }
    func putItemCacheEntry(id: ItemCacheEntryId, entry: CodableEntry) { cache[id] = entry }
    func removeItemCacheEntry(id: ItemCacheEntryId) { cache.removeValue(forKey: id) }
    func setMessageHistoryThreads(peerId: PeerId) -> [Int64] { [5, 9] }
    func addHole(peerId: PeerId, threadId: Int64?, namespace: Int32, space: HoleSpace, range: ClosedRange<Int32>) {
        holes.insert("\(peerId.value):\(threadId ?? 0)")
    }
    func removeHole(peerId: PeerId, threadId: Int64?, namespace: Int32, space: HoleSpace, range: ClosedRange<Int32>) {
        holes.remove("\(peerId.value):\(threadId ?? 0)")
    }
}
func check(_ value: @autoclosure () -> Bool, _ message: String) { precondition(value(), message) }

// TEST CASES
let id = PeerId(value: 1)
let member = TelegramChannel(id: id, participationStatus: .member)
let banned = TelegramChannel(id: id, participationStatus: .kicked)
let transaction = Transaction()
transaction.peers[id] = member
transaction.inclusions[id] = .included(group: "archive", pin: 3)
transaction.holes = ["1:0", "1:5", "1:9"]
donutgramUpdateBannedChat(transaction: transaction, previous: member, updated: banned)
check(transaction.cache.isEmpty, "disabled by default")
DGSimpleSettings.shared.keepBannedChats = true
donutgramUpdateBannedChat(transaction: transaction, previous: member, updated: banned)
transaction.peers[id] = banned
check(donutgramIsPreservedBannedChat(transaction: transaction, peerId: id), "ban archives an existing chat")
check(!shouldExcludePeerFromChatList(transaction: transaction, peerId: id), "sync keeps the archive")
check(transaction.inclusions[id] == .included(group: "archive", pin: 3), "keep folder and pin")
check(transaction.holes.isEmpty, "no unfillable root or forum history holes")
check(banned.participationStatus == .kicked, "membership must stay banned for input restrictions")

let reopened = Transaction()
reopened.peers = transaction.peers
reopened.inclusions = transaction.inclusions
reopened.cache = transaction.cache
DGSimpleSettings.shared.keepBannedChats = false
check(donutgramIsPreservedBannedChat(transaction: reopened, peerId: id), "stored archive survives reopening and disabling new captures")
check(!donutgramIsPreservedBannedChat(transaction: Transaction(), peerId: id, peer: banned), "account isolation")
reopened.inclusions[id] = .notIncluded
donutgramUpdateBannedChat(transaction: reopened, previous: banned, updated: banned)
check(!donutgramIsPreservedBannedChat(transaction: reopened, peerId: id), "manual deletion is not undone")
check(shouldExcludePeerFromChatList(transaction: reopened, peerId: id), "sync must not reinsert deleted archive")

donutgramUpdateBannedChat(transaction: transaction, previous: banned, updated: member)
transaction.peers[id] = member
check(transaction.cache.isEmpty, "rejoining removes the archive marker")
check(transaction.holes == ["1:0", "1:5", "1:9"], "rejoining resumes history sync")
check(!shouldExcludePeerFromChatList(transaction: transaction, peerId: id), "member is visible normally")

DGSimpleSettings.shared.keepBannedChats = true
let left = TelegramChannel(id: id, participationStatus: .left)
donutgramUpdateBannedChat(transaction: transaction, previous: member, updated: left)
check(transaction.cache.isEmpty, "voluntary leave is not a ban")
let unseen = Transaction()
donutgramUpdateBannedChat(transaction: unseen, previous: nil, updated: banned)
check(unseen.cache.isEmpty, "do not resurrect unknown or previewed banned chats")
let group = TelegramGroup(id: id, membership: .Member)
let removed = TelegramGroup(id: id, membership: .Removed)
donutgramUpdateBannedChat(transaction: transaction, previous: group, updated: removed)
transaction.peers[id] = removed
check(!shouldExcludePeerFromChatList(transaction: transaction, peerId: id), "basic groups are preserved too")
check(!donutgramPeerIsBanned(TelegramGroup(id: id, membership: .Removed, flags: .deactivated)), "migrated/deactivated groups are excluded")
check(!donutgramPeerIsBanned(TelegramGroup(id: id, membership: .Left)), "voluntary basic-group leave")
print("banned chat archive checks passed")
