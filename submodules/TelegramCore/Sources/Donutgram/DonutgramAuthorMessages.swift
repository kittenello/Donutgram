import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

public struct DonutgramAuthorMessagesResult {
    /// The author's messages in the chat, stored in the local database, newest first.
    public let messages: [Message]
    /// False when a page failed to load, so only part of them were found.
    public let isComplete: Bool
    /// True when only the newest messages are found because the author has more than `donutgramAuthorMessagesLimit`.
    public let reachedLimit: Bool
    /// True when only the newest messages are found because a private chat's history is longer than
    /// `donutgramAuthorMessagesHistoryScanLimit`, so its older part was not read through.
    public let reachedHistoryScanLimit: Bool
}

/// The most messages one «Выбрать все сообщения» selects. A long private chat holds tens of thousands of an
/// author's messages: hundreds of requests in a row, and a selection whose panel watches every message separately.
public let donutgramAuthorMessagesLimit = 10_000

private let donutgramAuthorMessagesPageLimit: Int32 = 100

/// How many messages of a private chat's history are read through at most, both sides together, so a chat where the
/// author wrote little does not page through a history of hundreds of thousands.
public let donutgramAuthorMessagesHistoryScanLimit = 50_000

private struct DonutgramAuthorMessagesPage {
    var ids: [MessageId]
    /// The server's exact count of the author's messages in the source, nil when it gave none or an estimate.
    var total: Int?
    var nextOffsetId: Int32?
    /// Messages the page held, the other side's included when the history is paged.
    var scannedCount: Int = 0
    var failed: Bool = false
}

/// Every message `authorId` wrote in `peerId` (in `threadId` when given), for «Выбрать сообщения: …».
///
/// The cloud history is paged with `messages.search` by `from_id`, a migrated group's history included, and
/// each page is stored like `getMessagesLoadIfNecessary` stores fetched messages, because forwarding and the
/// delete options read the selected messages from the database. Messages already stored are kept as they are.
/// A secret chat has no server history, so its messages are read locally; saved deleted messages are added
/// from the local store in both cases.
func _internal_donutgramAuthorMessages(account: Account, peerId: PeerId, threadId: Int64?, authorId: PeerId, sourceMessageId: MessageId?) -> Signal<DonutgramAuthorMessagesResult, NoError> {
    let accountPeerId = account.peerId
    let postbox = account.postbox
    let network = account.network

    if peerId.namespace == Namespaces.Peer.SecretChat {
        return postbox.transaction { transaction -> DonutgramAuthorMessagesResult in
            var messages: [Message] = []
            transaction.withAllMessages(peerId: peerId, { message in
                if message.author?.id == authorId {
                    messages.append(message)
                }
                return true
            })
            messages.sort(by: { $0.index > $1.index })
            let reachedLimit = messages.count > donutgramAuthorMessagesLimit
            return DonutgramAuthorMessagesResult(messages: Array(messages.prefix(donutgramAuthorMessagesLimit)), isComplete: true, reachedLimit: reachedLimit, reachedHistoryScanLimit: false)
        }
    }

    struct Source {
        let peer: Peer
        let inputPeer: Api.InputPeer
        let threadId: Int64?
        let topMsgId: Int32?
        let savedPeer: Api.InputPeer?
        /// A private chat is read through its whole history and filtered here. On a device `messages.search` by
        /// `from_id` found only part of the other user's messages there (no official client searches a private
        /// chat by sender), while the history holds all of them.
        let pagesHistory: Bool
    }

    return postbox.transaction { transaction -> (sources: [Source], fromPeer: Api.InputPeer?) in
        guard let peer = transaction.getPeer(peerId), let inputPeer = apiInputPeer(peer) else {
            return ([], nil)
        }
        let fromPeer: Api.InputPeer?
        if authorId == accountPeerId {
            fromPeer = .inputPeerSelf
        } else {
            // A member known only from a large group's messages has no access hash of its own; it is addressed through
            // the message it was seen in, as everywhere else in the core.
            fromPeer = transaction.getPeer(authorId).flatMap { apiInputPeer($0, sourceMessageId: sourceMessageId, transaction: transaction) }
        }

        // The same thread addressing as `_internal_searchMessages`: a channel's direct messages are keyed by the
        // user, everything else by the thread's top message.
        var savedPeer: Api.InputPeer?
        var topMsgId: Int32?
        if let threadId {
            if peer.isMonoForum {
                // Without the thread's user the search would cover the whole monoforum, and the selection is
                // what gets deleted, so nothing is found instead.
                guard let threadPeer = transaction.getPeer(PeerId(threadId)).flatMap(apiInputPeer) else {
                    return ([], fromPeer)
                }
                savedPeer = threadPeer
            } else {
                topMsgId = Int32(clamping: threadId)
            }
        }
        var sources = [Source(peer: peer, inputPeer: inputPeer, threadId: threadId, topMsgId: topMsgId, savedPeer: savedPeer, pagesHistory: peer is TelegramUser)]
        if threadId == nil, let cachedData = transaction.getPeerCachedData(peerId: peerId) as? CachedChannelData, let migrationReference = cachedData.migrationReference, let migratedPeer = transaction.getPeer(migrationReference.maxMessageId.peerId), let migratedInputPeer = apiInputPeer(migratedPeer) {
            sources.append(Source(peer: migratedPeer, inputPeer: migratedInputPeer, threadId: nil, topMsgId: nil, savedPeer: nil, pagesHistory: false))
        }
        return (sources, fromPeer)
    }
    |> mapToSignal { sources, fromPeer -> Signal<DonutgramAuthorMessagesResult, NoError> in
        // Neither the author nor the chat (or its thread) could be addressed, so the server was not asked at all.
        guard let fromPeer, !sources.isEmpty else {
            return .single(DonutgramAuthorMessagesResult(messages: [], isComplete: false, reachedLimit: false, reachedHistoryScanLimit: false))
        }

        func loadPage(_ source: Source, offsetId: Int32) -> Signal<DonutgramAuthorMessagesPage, NoError> {
            var flags: Int32 = 1 << 0
            if source.topMsgId != nil {
                flags |= 1 << 1
            }
            if source.savedPeer != nil {
                flags |= 1 << 2
            }
            let request: Signal<Api.messages.Messages, MTRpcError>
            if source.pagesHistory {
                request = network.request(Api.functions.messages.getHistory(peer: source.inputPeer, offsetId: offsetId, offsetDate: 0, addOffset: 0, limit: donutgramAuthorMessagesPageLimit, maxId: 0, minId: 0, hash: 0))
            } else {
                request = network.request(Api.functions.messages.search(flags: flags, peer: source.inputPeer, q: "", fromId: fromPeer, savedPeerId: source.savedPeer, savedReaction: nil, topMsgId: source.topMsgId, filter: .inputMessagesFilterEmpty, minDate: 0, maxDate: Int32.max - 1, offsetId: offsetId, addOffset: 0, limit: donutgramAuthorMessagesPageLimit, maxId: Int32.max - 1, minId: 0, hash: 0))
            }
            return request
            |> map(Optional.init)
            |> `catch` { _ -> Signal<Api.messages.Messages?, NoError> in
                return .single(nil)
            }
            |> mapToSignal { result -> Signal<DonutgramAuthorMessagesPage, NoError> in
                guard let result else {
                    return .single(DonutgramAuthorMessagesPage(ids: [], total: nil, nextOffsetId: nil, failed: true))
                }
                var apiMessages: [Api.Message] = []
                var chats: [Api.Chat] = []
                var users: [Api.User] = []
                var total: Int?
                // A plain `.messages` answer is the whole result; only a slice has further pages.
                var isComplete = false
                // An `inexact` count is an estimate that can be lower than the real one, so it must not end the paging.
                let inexactFlag: Int32 = 1 << 1
                switch result {
                case let .messages(data):
                    (apiMessages, chats, users) = (data.messages, data.chats, data.users)
                    isComplete = true
                case let .messagesSlice(data):
                    (apiMessages, chats, users) = (data.messages, data.chats, data.users)
                    total = (data.flags & inexactFlag) == 0 ? Int(data.count) : nil
                case let .channelMessages(data):
                    (apiMessages, chats, users) = (data.messages, data.chats, data.users)
                    total = (data.flags & inexactFlag) == 0 ? Int(data.count) : nil
                case .messagesNotModified:
                    isComplete = true
                }
                return postbox.transaction { transaction -> DonutgramAuthorMessagesPage in
                    updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: AccumulatedPeers(transaction: transaction, chats: chats, users: users))

                    var ids: [MessageId] = []
                    var pageIds: [MessageId] = []
                    var missingMessages: [StoreMessage] = []
                    for apiMessage in apiMessages {
                        guard let message = StoreMessage(apiMessage: apiMessage, accountPeerId: accountPeerId, peerIsForum: source.peer.isForumOrMonoForum), case let .Id(id) = message.id else {
                            continue
                        }
                        pageIds.append(id)
                        if source.pagesHistory && message.authorId != authorId {
                            continue
                        }
                        // A bot's topic is paged through the whole chat's history, which has no `top_msg_id`, so the
                        // other topics' messages are left out here.
                        if source.pagesHistory, let threadId = source.threadId, message.threadId != threadId {
                            continue
                        }
                        ids.append(id)
                        if !transaction.messageExists(id: id) {
                            missingMessages.append(message)
                        }
                    }
                    if !missingMessages.isEmpty {
                        let _ = transaction.addMessages(donutgramPreservingLocalState(transaction: transaction, messages: missingMessages), location: .Random)
                    }
                    var nextOffsetId = pageIds.map(\.id).min()
                    // Each page must move further back, or a server repeating a page would be paged forever.
                    if isComplete || (offsetId != 0 && (nextOffsetId ?? 0) >= offsetId) {
                        nextOffsetId = nil
                    }
                    // A history's count is the whole chat's, not the author's.
                    return DonutgramAuthorMessagesPage(ids: ids, total: source.pagesHistory ? nil : total, nextOffsetId: nextOffsetId, scannedCount: pageIds.count)
                }
            }
        }

        let loadedIds = Atomic<[MessageId]>(value: [])
        let didFail = Atomic<Bool>(value: false)
        let didReachLimit = Atomic<Bool>(value: false)
        let didReachHistoryScanLimit = Atomic<Bool>(value: false)
        let scannedCount = Atomic<Int>(value: 0)

        func finish() -> Signal<DonutgramAuthorMessagesResult, NoError> {
            return postbox.transaction { transaction -> DonutgramAuthorMessagesResult in
                var reachedLimit = didReachLimit.with { $0 }
                let reachedHistoryScanLimit = didReachHistoryScanLimit.with { $0 }
                // A reply thread's head is drawn without a selection checkbox, and an album head with all its items.
                // The chat leaves it out only while it is in the loaded window, so it is left out here as well.
                var seen = Set<MessageId>()
                for source in sources {
                    if let topMsgId = source.topMsgId {
                        let headId = MessageId(peerId: source.peer.id, namespace: Namespaces.Message.Cloud, id: topMsgId)
                        seen.insert(headId)
                        if let headGroup = transaction.getMessageGroup(headId) {
                            seen.formUnion(headGroup.map(\.id))
                        }
                    }
                }
                let excludedCount = seen.count
                var messages: [Message] = []
                // Pages come newest first, so the limit keeps the newest messages.
                for id in loadedIds.with({ $0 }) {
                    if seen.count - excludedCount >= donutgramAuthorMessagesLimit {
                        if !seen.contains(id) {
                            reachedLimit = true
                            break
                        }
                        continue
                    }
                    if seen.insert(id).inserted, let message = transaction.getMessage(id) {
                        messages.append(message)
                    }
                }
                let oldestIndex = messages.map(\.index).min()
                // A saved deleted message is no longer on the server, but the chat still shows it. Past the limit only
                // the ones among the newest are added, so the selection still ends where the loaded messages do.
                for source in sources {
                    for message in donutgramDeletedMessages(transaction: transaction, peerId: source.peer.id, fromId: authorId, threadId: source.threadId) {
                        if reachedLimit || reachedHistoryScanLimit, let oldestIndex, message.index < oldestIndex {
                            continue
                        }
                        if seen.insert(message.id).inserted {
                            messages.append(message)
                        }
                    }
                }
                messages.sort(by: { $0.index > $1.index })
                return DonutgramAuthorMessagesResult(messages: messages, isComplete: !didFail.with { $0 }, reachedLimit: reachedLimit, reachedHistoryScanLimit: reachedHistoryScanLimit && !reachedLimit)
            }
        }

        func loadSource(_ index: Int, offsetId: Int32) -> Signal<DonutgramAuthorMessagesResult, NoError> {
            let source = sources[index]
            return loadPage(source, offsetId: offsetId)
            |> mapToSignal { page -> Signal<DonutgramAuthorMessagesResult, NoError> in
                if page.failed {
                    let _ = didFail.swap(true)
                }
                let ids = loadedIds.modify { $0 + page.ids }
                let sourceIds = Set(ids.filter { $0.peerId == source.peer.id })
                let sourceCompleted = page.nextOffsetId == nil || (page.total.map { sourceIds.count >= $0 } ?? false)
                let scanned = scannedCount.modify { $0 + page.scannedCount }
                let hasMore = !sourceCompleted || index + 1 < sources.count
                if hasMore && Set(ids).count >= donutgramAuthorMessagesLimit {
                    let _ = didReachLimit.swap(true)
                    return finish()
                }
                if hasMore && scanned >= donutgramAuthorMessagesHistoryScanLimit {
                    let _ = didReachHistoryScanLimit.swap(true)
                    return finish()
                }
                if let nextOffsetId = page.nextOffsetId, !sourceCompleted {
                    return loadSource(index, offsetId: nextOffsetId)
                } else if index + 1 < sources.count {
                    return loadSource(index + 1, offsetId: 0)
                } else {
                    return finish()
                }
            }
        }

        return loadSource(0, offsetId: 0)
    }
}

public extension TelegramEngine.Messages {
    /// Every message of `authorId` in the chat (in the thread when `threadId` is given), loaded from the server
    /// page by page and stored locally, for selecting them all.
    /// `sourceMessageId` is a message of the author, used to address an author the account has no access hash for.
    func donutgramAuthorMessages(peerId: EnginePeer.Id, threadId: Int64?, authorId: EnginePeer.Id, sourceMessageId: EngineMessage.Id?) -> Signal<DonutgramAuthorMessagesResult, NoError> {
        return _internal_donutgramAuthorMessages(account: self.account, peerId: peerId, threadId: threadId, authorId: authorId, sourceMessageId: sourceMessageId)
    }
}
