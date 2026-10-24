import Foundation
import Postbox
import SwiftSignalKit
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
    guard let startedAt = DGSimpleSettings.shared.approximateLastSeenStartedAt else {
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
              message.timestamp > startedAt, message.timestamp <= now,
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

public func donutgramApproximateLastSeenTimestamp(_ presence: EnginePeer.Presence, relativeTo timestamp: Int32) -> Int32? {
    guard let startedAt = DGSimpleSettings.shared.approximateLastSeenStartedAt,
          case .recently = presence.status else {
        return nil
    }
    let lastMessage = presence.donutgramLastMessageTimestamp
    let age = Int64(timestamp) - Int64(lastMessage)
    guard lastMessage > startedAt, age >= 0, age < 3 * 24 * 60 * 60 else {
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
    |> mapToSignal { _ -> Signal<PeerView, NoError> in
        return account.viewTracker.peerView(peerId)
    }
}
