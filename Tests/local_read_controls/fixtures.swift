import Foundation

struct PeerId: Hashable {
    let value: Int64
    init(_ value: Int64) { self.value = value }
    var namespace: Int32 { Int32(value >> 32) }
    func toInt64() -> Int64 { value }
}
enum Namespaces {
    enum Peer {
        static let CloudUser: Int32 = 0
        static let CloudGroup: Int32 = 1
        static let CloudChannel: Int32 = 2
        static let SecretChat: Int32 = 3
    }
    enum Message { static let Cloud: Int32 = 0 }
}
struct MessageId {
    typealias Namespace = Int32
    let peerId: PeerId
    let namespace: Int32
    let id: Int32
}
struct MessageIndex { let id: MessageId }
struct FixturePeer { var isForumOrMonoForum = false }
enum PeerReadState: Equatable {
    case idBased(maxIncomingReadId: Int32, maxOutgoingReadId: Int32, maxKnownId: Int32, count: Int32, markedUnread: Bool)
    var count: Int32 { switch self { case let .idBased(_, _, _, count, _): return count } }
    var isUnread: Bool { switch self { case let .idBased(_, _, _, count, mark): return count > 0 || mark } }
}
enum PeerReadStateSynchronizationOperation { case Push; case Validate }
final class Transaction {
    var states: [PeerId: PeerReadState] = [:]
    var peers: [PeerId: FixturePeer] = [:]
    var operations: [PeerId: PeerReadStateSynchronizationOperation] = [:]
    var tops: [PeerId: Int32] = [:]
    var archived: Set<PeerId> = []
    func getPeer(_ id: PeerId) -> FixturePeer? { peers[id] }
    func getPeerChatListIndex(_ id: PeerId) -> Int? { peers[id] == nil ? nil : 1 }
    func getPeerReadStates(_ id: PeerId) -> [(Int32, PeerReadState)]? {
        states[id].map { [(Namespaces.Message.Cloud, $0)] }
    }
    func getPeerReadStateSynchronizationOperation(_ id: PeerId) -> PeerReadStateSynchronizationOperation? { operations[id] }
    func getTopPeerMessageIndex(peerId: PeerId, namespace: Int32) -> MessageIndex? {
        tops[peerId].map { MessageIndex(id: MessageId(peerId: peerId, namespace: namespace, id: $0)) }
    }
    func applyIncomingReadMaxId(_ id: MessageId) {
        guard case let .idBased(incoming, outgoing, known, count, _)? = states[id.peerId] else { return }
        states[id.peerId] = .idBased(maxIncomingReadId: max(incoming, id.id), maxOutgoingReadId: outgoing, maxKnownId: known, count: max(0, count - max(0, id.id - incoming)), markedUnread: false)
    }
    func resetIncomingReadStates(_ new: [PeerId: [Int32: PeerReadState]]) {
        for (peer, namespaces) in new {
            states[peer] = namespaces[Namespaces.Message.Cloud]
            operations.removeValue(forKey: peer)
        }
    }
    func setNeedsIncomingReadStateSynchronization(_ id: PeerId) { operations[id] = .Validate }
    func getUnreadChatListPeerIds(groupId: PeerGroupId, filterPredicate: Int?, additionalFilter: Int?, stopOnFirstMatch: Bool) -> [PeerId] {
        states.filter { $0.value.isUnread && (archived.contains($0.key) == (groupId != .root)) }.map { $0.key }
    }
}
enum PeerGroupId: Equatable { case root; case group(Int32) }
enum NoError: Error {}
struct Signal<Value, Failure: Error> { let value: Value }
final class Postbox {
    let fixture = Transaction()
    func transaction<Value>(_ action: (Transaction) -> Value) -> Signal<Value, NoError> { Signal(value: action(fixture)) }
}
func donutgramGhostModeBlocksContentReads() -> Bool {
    DGSimpleSettings.shared.ghostModeEnabled && !DGSimpleSettings.shared.ghostReadMessages
}

// PRODUCTION

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
}
let account = PeerId(990001)
let peer = PeerId(990002)
let box = Postbox()
let t = box.fixture
func seed(_ id: PeerId, count: Int32 = 80, mark: Bool = true) {
    t.peers[id] = FixturePeer()
    t.states[id] = .idBased(maxIncomingReadId: 20, maxOutgoingReadId: 8, maxKnownId: 100, count: count, markedUnread: mark)
    t.tops[id] = 97
}
DGSimpleSettings.shared.ghostModeEnabled = false
seed(peer)
check(donutgramReadChatLocally(transaction: t, accountPeerId: account, peerId: peer), "local read should work without ghost mode")
check(t.states[peer]?.count == 0 && t.states[peer]?.isUnread == false, "clear count and manual unread mark")
check(t.operations[peer] == nil, "no server read operation")
var read = donutgramGhostLocalReadState(accountPeerId: account, peerId: peer)!
check(read.isExplicit && read.maxIncomingReadId == 100 && read.serverMaxIncomingReadId == 20 && read.readCount == 80, "preserve baseline with holes in loaded history")
donutgramRestoreGhostLocalReads(transaction: t, accountPeerId: account)
check(t.states[peer]?.count == 0, "disabling ghost mode must preserve an explicit local read")

// A server refresh after three new messages must retain those three as unread.
let localCount: Int32 = 3
t.resetIncomingReadStates([peer: [0: .idBased(maxIncomingReadId: 20, maxOutgoingReadId: 8, maxKnownId: 103, count: 83, markedUnread: true)]])
donutgramGhostLocalReadDidApplyServerState(transaction: t, accountPeerId: account, peerId: peer, serverMaxIncomingReadId: 20, serverCount: 83, serverMarkedUnread: true, localCount: localCount)
check(t.states[peer]?.count == 3, "new incoming messages remain unread after server refresh")
check(donutgramGhostLocalReadState(accountPeerId: account, peerId: peer)?.isExplicit == true, "server refresh preserves explicit flag")
check(donutgramReadChatLocally(transaction: t, accountPeerId: account, peerId: peer), "repeat read")
check(donutgramGhostLocalReadState(accountPeerId: account, peerId: peer)?.readCount == 83, "repeat reads retain the full server baseline")
check(donutgramGhostLocalReadMarkUnread(transaction: t, accountPeerId: account, peerId: peer), "mark unread restores the server baseline")
check(t.states[peer]?.count == 83 && donutgramGhostLocalReadState(accountPeerId: account, peerId: peer) == nil, "restore without creating a server read")

seed(peer)
check(donutgramReadChatLocally(transaction: t, accountPeerId: account, peerId: peer), "read before explicit server action")
donutgramGhostLocalReadWillReadOnServer(transaction: t, accountPeerId: account, peerId: peer)
check(t.states[peer]?.count == 80 && donutgramGhostLocalReadState(accountPeerId: account, peerId: peer) == nil, "explicit server read restores the baseline first")

seed(peer)
t.operations[peer] = .Push
check(!donutgramReadChatLocally(transaction: t, accountPeerId: account, peerId: peer) && t.states[peer]?.count == 80, "pending server read must not capture a local read")
t.operations[peer] = nil
let archived = PeerId((Int64(Namespaces.Peer.CloudChannel) << 32) | 990003)
seed(archived)
t.archived.insert(archived)
check(_internal_donutgramReadAllMessagesLocally(postbox: box, accountPeerId: account).value == 0, "main and archive both read locally")
check(t.states[peer]?.count == 0 && t.states[archived]?.count == 0, "bulk read includes archive")
check(donutgramGhostLocalReadState(accountPeerId: PeerId(990004), peerId: peer) == nil, "account isolation")

let secret = PeerId((Int64(Namespaces.Peer.SecretChat) << 32) | 990005)
seed(secret)
let forum = PeerId((Int64(Namespaces.Peer.CloudChannel) << 32) | 990006)
seed(forum)
t.peers[forum]?.isForumOrMonoForum = true
check(_internal_donutgramReadAllMessagesLocally(postbox: box, accountPeerId: account).value == 2, "unsupported chats reported instead of false success")
check(t.states[secret]?.count == 80 && t.states[forum]?.count == 80, "unsupported chats unchanged")

// Real settings persistence in a separate process, and compatibility with old rows.
let mode = CommandLine.arguments[1]
let suite = CommandLine.arguments[2]
let defaults = UserDefaults(suiteName: suite)!
let settings = DGSimpleSettings(defaults: defaults)
if mode == "write" {
    defaults.removePersistentDomain(forName: suite)
    check(!settings.hideGiftButton, "gift button visible by default")
    settings.hideGiftButton = true
    settings.hideArchive = true
    settings.setGhostLocalRead(read, accountPeerId: 17, peerId: 18)
    defaults.set(["20": [30, 10, 20, 0, 0]], forKey: "donutgram.ghost.localReads.19")
    defaults.synchronize()
} else {
    check(settings.hideGiftButton && settings.hideArchive, "visibility preferences survive process restart")
    check(settings.ghostLocalRead(accountPeerId: 17, peerId: 18) == read, "explicit local read survives process restart")
    check(settings.ghostLocalRead(accountPeerId: 19, peerId: 20)?.isExplicit == false, "old five-field local reads still load")
    settings.hideGiftButton = false
    check(!settings.hideGiftButton, "gift button can be restored")
    defaults.removePersistentDomain(forName: suite)
}
for (id, _) in DGSimpleSettings.shared.ghostLocalReads(accountPeerId: account.toInt64()) {
    DGSimpleSettings.shared.setGhostLocalRead(nil, accountPeerId: account.toInt64(), peerId: id)
}
print("local read and visibility checks passed (\(mode))")
