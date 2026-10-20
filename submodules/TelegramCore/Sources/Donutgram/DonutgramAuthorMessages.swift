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
}

private let donutgramAuthorMessagesPageLimit: Int32 = 100

private struct DonutgramAuthorMessagesPage {
    var ids: [MessageId]
    /// The server's exact count of the author's messages in the source, nil when it gave none or an estimate.
    var total: Int?
    var nextOffsetId: Int32?
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
            return DonutgramAuthorMessagesResult(messages: messages, isComplete: true)
        }
    }

    struct Source {
        let peer: Peer
        let inputPeer: Api.InputPeer
        let threadId: Int64?
        let topMsgId: Int32?
        let savedPeer: Api.InputPeer?
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
                savedPeer = transaction.getPeer(PeerId(threadId)).flatMap(apiInputPeer)
            } else {
                topMsgId = Int32(clamping: threadId)
            }
        }
        var sources = [Source(peer: peer, inputPeer: inputPeer, threadId: threadId, topMsgId: topMsgId, savedPeer: savedPeer)]
        if threadId == nil, let cachedData = transaction.getPeerCachedData(peerId: peerId) as? CachedChannelData, let migrationReference = cachedData.migrationReference, let migratedPeer = transaction.getPeer(migrationReference.maxMessageId.peerId), let migratedInputPeer = apiInputPeer(migratedPeer) {
            sources.append(Source(peer: migratedPeer, inputPeer: migratedInputPeer, threadId: nil, topMsgId: nil, savedPeer: nil))
        }
        return (sources, fromPeer)
    }
    |> mapToSignal { sources, fromPeer -> Signal<DonutgramAuthorMessagesResult, NoError> in
        guard let fromPeer, !sources.isEmpty else {
            return .single(DonutgramAuthorMessagesResult(messages: [], isComplete: fromPeer != nil))
        }

        func loadPage(_ source: Source, offsetId: Int32) -> Signal<DonutgramAuthorMessagesPage, NoError> {
            var flags: Int32 = 1 << 0
            if source.topMsgId != nil {
                flags |= 1 << 1
            }
            if source.savedPeer != nil {
                flags |= 1 << 2
            }
            return network.request(Api.functions.messages.search(flags: flags, peer: source.inputPeer, q: "", fromId: fromPeer, savedPeerId: source.savedPeer, savedReaction: nil, topMsgId: source.topMsgId, filter: .inputMessagesFilterEmpty, minDate: 0, maxDate: Int32.max - 1, offsetId: offsetId, addOffset: 0, limit: donutgramAuthorMessagesPageLimit, maxId: Int32.max - 1, minId: 0, hash: 0))
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
                    var missingMessages: [StoreMessage] = []
                    for apiMessage in apiMessages {
                        guard let message = StoreMessage(apiMessage: apiMessage, accountPeerId: accountPeerId, peerIsForum: source.peer.isForumOrMonoForum), case let .Id(id) = message.id else {
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
                    var nextOffsetId = ids.map(\.id).min()
                    // Each page must move further back, or a server repeating a page would be paged forever.
                    if isComplete || (offsetId != 0 && (nextOffsetId ?? 0) >= offsetId) {
                        nextOffsetId = nil
                    }
                    return DonutgramAuthorMessagesPage(ids: ids, total: total, nextOffsetId: nextOffsetId)
                }
            }
        }

        let loadedIds = Atomic<[MessageId]>(value: [])
        let didFail = Atomic<Bool>(value: false)

        func finish() -> Signal<DonutgramAuthorMessagesResult, NoError> {
            return postbox.transaction { transaction -> DonutgramAuthorMessagesResult in
                var seen = Set<MessageId>()
                var messages: [Message] = []
                for id in loadedIds.with({ $0 }) {
                    if seen.insert(id).inserted, let message = transaction.getMessage(id) {
                        messages.append(message)
                    }
                }
                // A saved deleted message is no longer on the server, but the chat still shows it.
                for source in sources {
                    for message in donutgramDeletedMessages(transaction: transaction, peerId: source.peer.id, fromId: authorId, threadId: source.threadId) {
                        if seen.insert(message.id).inserted {
                            messages.append(message)
                        }
                    }
                }
                messages.sort(by: { $0.index > $1.index })
                return DonutgramAuthorMessagesResult(messages: messages, isComplete: !didFail.with { $0 })
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
