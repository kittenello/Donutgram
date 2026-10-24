import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi
internal import MtProtoKit
import DGSimpleSettings

func donutgramActivityGroup(_ peer: Peer?) -> Bool {
    if let group = peer as? TelegramGroup {
        return group.membership == .Member
    }
    if let channel = peer as? TelegramChannel, case .group = channel.info {
        return channel.participationStatus == .member
    }
    return false
}

func donutgramRecordMessageActivity(transaction: Transaction, accountPeerId: PeerId, messages: [StoreMessage]) {
    guard DGSimpleSettings.shared.approximateLastSeen else {
        return
    }
    let now = Int32(Date().timeIntervalSince1970)
    var timestamps: [PeerId: Int32] = [:]
    for message in messages {
        guard case let .Id(id) = message.id, id.namespace == Namespaces.Message.Cloud,
              let authorId = message.authorId, authorId != accountPeerId,
              authorId.namespace == Namespaces.Peer.CloudUser,
              let author = transaction.getPeer(authorId) as? TelegramUser,
              author.botInfo == nil, !author.isDeleted, !author.flags.contains(.isSupport),
              message.timestamp > 0, message.timestamp <= now,
              !message.flags.contains(.WasScheduled) else {
            continue
        }
        if id.peerId != authorId && !donutgramActivityGroup(transaction.getPeer(id.peerId)) {
            continue
        }
        if message.media.contains(where: { $0 is TelegramMediaAction }) || message.attributes.contains(where: {
            ($0 as? NotificationInfoMessageAttribute)?.flags.contains(.automaticMessage) == true
        }) {
            continue
        }
        timestamps[authorId] = max(timestamps[authorId] ?? 0, message.timestamp)
    }
    for (peerId, timestamp) in timestamps {
        let previous = transaction.getPeerPresence(peerId: peerId) as? TelegramUserPresence
        guard timestamp > (previous?.donutgramLastMessageTimestamp ?? 0) else {
            continue
        }
        let updated = TelegramUserPresence(status: previous?.status ?? .none, lastActivity: previous?.lastActivity ?? 0, donutgramLastMessageTimestamp: timestamp)
        transaction.updatePeerPresencesInternal(presences: [peerId: updated], merge: { _, updated in
            return updated
        })
    }
}

private func donutgramSearchMessageActivity(account: Account, peerId: PeerId, authorId: PeerId) -> Signal<Bool, NoError> {
    return account.postbox.transaction { transaction -> (Api.InputPeer, Api.InputPeer)? in
        guard let peer = transaction.getPeer(peerId),
              peerId == authorId || donutgramActivityGroup(peer),
              let inputPeer = apiInputPeer(peer),
              let inputAuthor = transaction.getPeer(authorId).flatMap(apiInputPeer) else {
            return nil
        }
        return (inputPeer, inputAuthor)
    }
    |> mapToSignal { inputs -> Signal<Bool, NoError> in
        guard let (inputPeer, inputAuthor) = inputs, DGSimpleSettings.shared.approximateLastSeen else {
            return .single(true)
        }
        return account.network.request(Api.functions.messages.search(flags: 1 << 0, peer: inputPeer, q: "", fromId: inputAuthor, savedPeerId: nil, savedReaction: nil, topMsgId: nil, filter: .inputMessagesFilterEmpty, minDate: 0, maxDate: 0, offsetId: 0, addOffset: 0, limit: 10, maxId: 0, minId: 0, hash: 0), automaticFloodWait: false)
        |> map { (Optional($0), true) }
        |> `catch` { error -> Signal<(Api.messages.Messages?, Bool), NoError> in
            return .single((nil, !error.errorDescription.hasPrefix("FLOOD_WAIT")))
        }
        |> mapToSignal { result, canContinue -> Signal<Bool, NoError> in
            guard let result else {
                return .single(canContinue)
            }
            return account.postbox.transaction { transaction -> Bool in
                let messages: [Api.Message]
                let chats: [Api.Chat]
                let users: [Api.User]
                switch result {
                case let .messages(data):
                    (messages, chats, users) = (data.messages, data.chats, data.users)
                case let .messagesSlice(data):
                    (messages, chats, users) = (data.messages, data.chats, data.users)
                case let .channelMessages(data):
                    (messages, chats, users) = (data.messages, data.chats, data.users)
                case .messagesNotModified:
                    return true
                }
                updatePeers(transaction: transaction, accountPeerId: account.peerId, peers: AccumulatedPeers(transaction: transaction, chats: chats, users: users))
                let isForum = transaction.getPeer(peerId)?.isForumOrMonoForum ?? false
                let parsed = messages.compactMap { StoreMessage(apiMessage: $0, accountPeerId: account.peerId, peerIsForum: isForum) }.filter { $0.authorId == authorId && $0.id.peerId == peerId }
                donutgramRecordMessageActivity(transaction: transaction, accountPeerId: account.peerId, messages: parsed)
                return true
            }
        }
    }
}

private func donutgramSearchActivityGroups(account: Account, authorId: PeerId, peerIds: ArraySlice<PeerId>) -> Signal<Bool, NoError> {
    guard let peerId = peerIds.first, DGSimpleSettings.shared.approximateLastSeen else {
        return .single(true)
    }
    return donutgramSearchMessageActivity(account: account, peerId: peerId, authorId: authorId)
    |> mapToSignal { success -> Signal<Bool, NoError> in
        guard success else {
            return .single(false)
        }
        return donutgramSearchActivityGroups(account: account, authorId: authorId, peerIds: peerIds.dropFirst())
        |> delay(0.2, queue: Queue.concurrentDefaultQueue())
    }
}

private func donutgramSearchCommonActivity(account: Account, authorId: PeerId, inputUser: Api.InputUser, maxId: Int64 = 0) -> Signal<Bool, NoError> {
    guard DGSimpleSettings.shared.approximateLastSeen else {
        return .single(true)
    }
    return account.network.request(Api.functions.messages.getCommonChats(userId: inputUser, maxId: maxId, limit: 100), automaticFloodWait: false)
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.messages.Chats?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<Bool, NoError> in
        guard let result else {
            return .single(false)
        }
        let chats: [Api.Chat]
        let canLoadMore: Bool
        switch result {
        case let .chats(data):
            chats = data.chats
            canLoadMore = false
        case let .chatsSlice(data):
            chats = data.chats
            canLoadMore = !chats.isEmpty
        }
        return account.postbox.transaction { transaction -> [PeerId] in
            updatePeers(transaction: transaction, accountPeerId: account.peerId, peers: AccumulatedPeers(transaction: transaction, chats: chats, users: []))
            return chats.map { $0.peerId }.filter { donutgramActivityGroup(transaction.getPeer($0)) }
        }
        |> mapToSignal { peerIds -> Signal<Bool, NoError> in
            return donutgramSearchActivityGroups(account: account, authorId: authorId, peerIds: peerIds[...])
            |> mapToSignal { success -> Signal<Bool, NoError> in
                let nextId = chats.last?.peerId.id._internalGetInt64Value() ?? 0
                guard success, canLoadMore, nextId != 0, nextId != maxId else {
                    return .single(success)
                }
                return donutgramSearchCommonActivity(account: account, authorId: authorId, inputUser: inputUser, maxId: nextId)
            }
        }
    }
}

private let donutgramActivitySearchTimes = Atomic<[String: Double]>(value: [:])

private func donutgramRefreshMessageActivity(account: Account, peerId: PeerId) -> Signal<Bool, NoError> {
    return account.postbox.transaction { transaction -> (Api.InputUser, String, Double)? in
        guard DGSimpleSettings.shared.approximateLastSeen,
              peerId != account.peerId, peerId.namespace == Namespaces.Peer.CloudUser,
              let user = transaction.getPeer(peerId) as? TelegramUser,
              user.botInfo == nil, !user.isDeleted, !user.flags.contains(.isSupport),
              let presence = transaction.getPeerPresence(peerId: peerId) as? TelegramUserPresence,
              case .recently = presence.status,
              let inputUser = apiInputUser(user) else {
            return nil
        }
        let now = Date().timeIntervalSince1970
        let key = "\(account.id.int64):\(peerId.toInt64())"
        var allowed = false
        let _ = donutgramActivitySearchTimes.modify { times -> [String: Double] in
            var times = times.filter { now - $0.value < 300.0 }
            if times[key] == nil {
                times[key] = now
                allowed = true
            }
            return times
        }
        return allowed ? (inputUser, key, now) : nil
    }
    |> mapToSignal { inputs -> Signal<Bool, NoError> in
        guard let (inputUser, key, startedAt) = inputs else {
            return .single(true)
        }
        let finished = Atomic<Bool>(value: false)
        return donutgramSearchMessageActivity(account: account, peerId: peerId, authorId: peerId)
        |> mapToSignal { success -> Signal<Bool, NoError> in
            guard success else {
                return .single(false)
            }
            return donutgramSearchCommonActivity(account: account, authorId: peerId, inputUser: inputUser)
        }
        |> beforeNext { _ in
            let _ = finished.swap(true)
        }
        |> afterDisposed {
            if !finished.with({ $0 }) {
                let _ = donutgramActivitySearchTimes.modify { times -> [String: Double] in
                    var times = times
                    if times[key] == startedAt {
                        times.removeValue(forKey: key)
                    }
                    return times
                }
            }
        }
    }
}

public func donutgramApproximateLastSeenTimestamp(_ presence: EnginePeer.Presence, relativeTo timestamp: Int32) -> Int32? {
    guard case .recently = presence.status else {
        return nil
    }
    let lastMessage = presence.donutgramLastMessageTimestamp
    let age = Int64(timestamp) - Int64(lastMessage)
    guard lastMessage > 0, age >= 0, age < 3 * 24 * 60 * 60 else {
        return nil
    }
    return lastMessage
}

public func donutgramActivityPeerView(account: Account, peerId: PeerId) -> Signal<PeerView, NoError> {
    let enabled = Signal<Bool, NoError> { subscriber in
        let observer = NotificationCenter.default.addObserver(forName: DGSimpleSettings.didChangeNotification, object: DGSimpleSettings.shared, queue: nil) { _ in
            subscriber.putNext(DGSimpleSettings.shared.approximateLastSeen)
        }
        subscriber.putNext(DGSimpleSettings.shared.approximateLastSeen)
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    |> distinctUntilChanged
    return enabled
    |> mapToSignal { enabled -> Signal<PeerView, NoError> in
        return Signal { subscriber in
            let refresh = MetaDisposable()
            var searchStarted = false
            let view = account.viewTracker.peerView(peerId).start(next: { view in
                subscriber.putNext(view)
                if enabled, !searchStarted, let presence = view.peerPresences[peerId] as? TelegramUserPresence, case .recently = presence.status {
                    searchStarted = true
                    refresh.set(donutgramRefreshMessageActivity(account: account, peerId: peerId).start())
                }
            })
            return ActionDisposable {
                view.dispose()
                refresh.dispose()
            }
        }
    }
}
