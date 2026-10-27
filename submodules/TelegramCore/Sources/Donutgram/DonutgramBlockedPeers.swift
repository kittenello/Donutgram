import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi
import DGSimpleSettings

/// Keeps the account's blocked peers in `DGSimpleSettings` for «Скрывать сообщения заблокированных»: the whole list from
/// the server once per launch while the switch is on, and again when it is turned on. Blocks and unblocks made later,
/// here or on another device, are applied one by one (`donutgramUpdateBlockedPeer` and the `updatePeerBlocked` update),
/// so a chat never waits for the list, works offline and doesn't flash its hidden messages.
func managedDonutgramBlockedPeers(postbox: Postbox, network: Network, accountPeerId: PeerId) -> Signal<Void, NoError> {
    let isEnabled = Signal<Bool, NoError> { subscriber in
        subscriber.putNext(DGSimpleSettings.shared.hideBlockedMessages)
        let observer = NotificationCenter.default.addObserver(forName: DGSimpleSettings.didChangeNotification, object: nil, queue: nil, using: { _ in
            subscriber.putNext(DGSimpleSettings.shared.hideBlockedMessages)
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    |> distinctUntilChanged

    return isEnabled
    |> mapToSignal { isEnabled -> Signal<Void, NoError> in
        if !isEnabled {
            return .complete()
        }
        return donutgramFetchBlockedPeerIds(postbox: postbox, network: network, accountPeerId: accountPeerId)
        |> map { peerIds -> Void in
            if let peerIds {
                DGSimpleSettings.shared.setBlockedPeerIds(peerIds, accountId: accountPeerId.toInt64())
            }
        }
    }
}

/// Applies a block or unblock the account made to the list `managedDonutgramBlockedPeers` keeps. A bot is never added:
/// stopping a bot blocks it, and its messages in groups, captchas among them, must stay.
func donutgramUpdateBlockedPeer(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId, isBlocked: Bool) {
    let isBot = (transaction.getPeer(peerId) as? TelegramUser)?.botInfo != nil
    DGSimpleSettings.shared.setPeerBlocked(isBlocked && !isBot, peerId: peerId.toInt64(), accountId: accountPeerId.toInt64())
}

/// The account's whole blocked list, page by page, without bots. Nil when the account is frozen.
private func donutgramFetchBlockedPeerIds(postbox: Postbox, network: Network, accountPeerId: PeerId) -> Signal<Set<Int64>?, NoError> {
    func fetch(offset: Int32, collected: Set<Int64>) -> Signal<Set<Int64>?, NoError> {
        return network.request(Api.functions.contacts.getBlocked(flags: 0, offset: offset, limit: 200))
        |> retryRequestIfNotFrozen
        |> mapToSignal { result -> Signal<Set<Int64>?, NoError> in
            guard let result else {
                return .single(nil)
            }
            return postbox.transaction { transaction -> (peerIds: Set<Int64>, received: Int32, isLast: Bool) in
                var peerIds = collected
                let insert: (PeerId) -> Void = { peerId in
                    if let user = transaction.getPeer(peerId) as? TelegramUser, user.botInfo != nil {
                        return
                    }
                    peerIds.insert(peerId.toInt64())
                }
                var count = 0
                var totalCount: Int32?
                switch result {
                case let .blocked(blockedData):
                    updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: AccumulatedPeers(transaction: transaction, chats: blockedData.chats, users: blockedData.users))
                    for blockedPeer in blockedData.blocked {
                        switch blockedPeer {
                        case let .peerBlocked(peerBlockedData):
                            insert(peerBlockedData.peerId.peerId)
                        }
                    }
                    count = blockedData.blocked.count
                case let .blockedSlice(blockedSliceData):
                    updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: AccumulatedPeers(transaction: transaction, chats: blockedSliceData.chats, users: blockedSliceData.users))
                    for blockedPeer in blockedSliceData.blocked {
                        switch blockedPeer {
                        case let .peerBlocked(peerBlockedData):
                            insert(peerBlockedData.peerId.peerId)
                        }
                    }
                    count = blockedSliceData.blocked.count
                    totalCount = blockedSliceData.count
                }
                // The next page starts after what the server sent, not after the peers kept: bots are skipped.
                let received = offset + Int32(count)
                var isLast = true
                if let totalCount, count != 0 {
                    isLast = received >= totalCount
                }
                return (peerIds, received, isLast)
            }
            |> mapToSignal { page -> Signal<Set<Int64>?, NoError> in
                if page.isLast {
                    return .single(page.peerIds)
                }
                return fetch(offset: page.received, collected: page.peerIds)
            }
        }
    }
    return fetch(offset: 0, collected: Set())
}
