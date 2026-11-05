
struct StoredDraftData {
    let synchronizeableInputState: DraftInputState?
    let mediaDraftState: MediaDraft?
    struct MediaDraft { let timestamp: Int32 }
}

struct StoredPeerChatInterfaceState {
    let overrideChatTimestamp: Int32?
    let historyScrollMessageIndex: Int?
    let associatedMessageIds: [Int]
    let data: StoredDraftData?
}

struct FixtureThreadId: Hashable {
    let peerId: Int
    let threadId: Int64
}

func _internal_decodeStoredChatInterfaceState(state: StoredPeerChatInterfaceState) -> StoredDraftData? {
    return state.data
}

final class Transaction {
    var peers: [Int: StoredPeerChatInterfaceState] = [:]
    var threads: [FixtureThreadId: StoredPeerChatInterfaceState] = [:]
    var writes = 0
    func getPeerChatInterfaceStateIds() -> [Int] { Array(self.peers.keys) }
    func getPeerChatThreadInterfaceStateIds() -> [FixtureThreadId] { Array(self.threads.keys) }
    func getPeerChatInterfaceState(_ id: Int) -> StoredPeerChatInterfaceState? { self.peers[id] }
    func getPeerChatThreadInterfaceState(_ id: Int, threadId: Int64) -> StoredPeerChatInterfaceState? {
        self.threads[FixtureThreadId(peerId: id, threadId: threadId)]
    }
    func setPeerChatInterfaceState(_ id: Int, state: StoredPeerChatInterfaceState?) {
        self.peers[id] = state
        self.writes += 1
    }
    func setPeerChatThreadInterfaceState(_ id: Int, threadId: Int64, state: StoredPeerChatInterfaceState?) {
        self.threads[FixtureThreadId(peerId: id, threadId: threadId)] = state
        self.writes += 1
    }
}

for mediaTimestamp in [nil, 80, 120] as [Int32?] {
    let input = DraftInputState(replySubject: 42, content: .textEntities("", []), timestamp: 100, messageEffectId: nil, suggestedPost: nil)
    let data = StoredDraftData(synchronizeableInputState: input, mediaDraftState: mediaTimestamp.map { StoredDraftData.MediaDraft(timestamp: $0) })
    let saved = StoredPeerChatInterfaceState(overrideChatTimestamp: max(100, mediaTimestamp ?? 100), historyScrollMessageIndex: 12, associatedMessageIds: [42], data: data)
    let transaction = Transaction()
    transaction.peers[1] = saved
    let thread = FixtureThreadId(peerId: 2, threadId: 3)
    transaction.threads[thread] = saved
    for hidden in [true, false, true, false] {
        donutgramRefreshEmptyReplyDraftTimestamps(transaction: transaction, hidingEmptyReplies: hidden)
        for state in [transaction.peers[1]!, transaction.threads[thread]!] {
            let expected: Int32? = hidden ? mediaTimestamp : max(100, mediaTimestamp ?? 100)
            check(state.overrideChatTimestamp == expected, "toggling updates saved peer and topic timestamps in both directions")
            check(state.historyScrollMessageIndex == 12 && state.associatedMessageIds == [42], "the selected reply and scroll position survive")
            check(state.data?.synchronizeableInputState?.replySubject == 42, "the reply is kept in the stored data")
            check(state.data?.synchronizeableInputState?.timestamp == 100, "the original draft time is preserved")
            check(state.data?.mediaDraftState?.timestamp == mediaTimestamp, "an attached media draft is kept")
        }
        let writes = transaction.writes
        donutgramRefreshEmptyReplyDraftTimestamps(transaction: transaction, hidingEmptyReplies: hidden)
        check(transaction.writes == writes, "unchanged timestamps are not written again")
    }
}
let unaffectedTransaction = Transaction()
let textInput = DraftInputState(replySubject: 42, content: .textEntities("text", []), timestamp: 100, messageEffectId: nil, suggestedPost: nil)
unaffectedTransaction.peers[1] = StoredPeerChatInterfaceState(overrideChatTimestamp: 100, historyScrollMessageIndex: 12, associatedMessageIds: [42], data: StoredDraftData(synchronizeableInputState: textInput, mediaDraftState: nil))
unaffectedTransaction.peers[2] = StoredPeerChatInterfaceState(overrideChatTimestamp: nil, historyScrollMessageIndex: nil, associatedMessageIds: [], data: nil)
donutgramRefreshEmptyReplyDraftTimestamps(transaction: unaffectedTransaction, hidingEmptyReplies: true)
check(unaffectedTransaction.writes == 0, "text drafts and unreadable states are untouched")
print("stored peer and topic reply draft toggle checks passed")
