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
    var timestamps: [PeerId: Int32] = [:]
    for message in messages {
        // Message dates are server time, never compared with this device's clock: one that runs behind would drop every new message.
        guard case let .Id(id) = message.id, id.namespace == Namespaces.Message.Cloud,
              let authorId = message.authorId, authorId != accountPeerId,
              authorId.namespace == Namespaces.Peer.CloudUser,
              let author = transaction.getPeer(authorId) as? TelegramUser,
              author.botInfo == nil, !author.isDeleted, !author.flags.contains(.isSupport),
              message.timestamp > startedAt,
              !message.flags.contains(.WasScheduled) else {
            continue
        }
        if id.peerId != authorId && !donutgramActivityGroup(transaction.getPeer(id.peerId)) {
            continue
        }
        // Away and greeting messages and a business account's chatbot replies are sent without the person.
        if message.media.contains(where: { $0 is TelegramMediaAction }) || message.attributes.contains(where: {
            $0 is InlineBusinessBotMessageAttribute || ($0 as? NotificationInfoMessageAttribute)?.flags.contains(.automaticMessage) == true
        }) {
            continue
        }
        timestamps[authorId] = max(timestamps[authorId] ?? 0, message.timestamp)
    }
    for (peerId, timestamp) in timestamps {
        // Only a presence the server gave is updated: a made-up one would keep a min user's status from being stored (UpdatePeers).
        guard let previous = transaction.getPeerPresence(peerId: peerId) as? TelegramUserPresence, timestamp > previous.donutgramLastMessageTimestamp else {
            continue
        }
        let updated = TelegramUserPresence(status: previous.status, lastActivity: previous.lastActivity, donutgramLastMessageTimestamp: timestamp)
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
