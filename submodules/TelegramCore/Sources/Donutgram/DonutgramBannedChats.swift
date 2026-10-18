import Foundation
import Postbox
import DGSimpleSettings

private struct DonutgramBannedChat: Codable {
    let saved: Bool
}

private func donutgramBannedChatCacheId(_ peerId: PeerId) -> ItemCacheEntryId {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.toInt64())
    return ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.donutgramBannedChats, key: key)
}

public func donutgramPeerIsBanned(_ peer: Peer?) -> Bool {
    if let group = peer as? TelegramGroup {
        return group.membership == .Removed && !group.flags.contains(.deactivated)
    } else if let channel = peer as? TelegramChannel {
        return channel.participationStatus == .kicked
    }
    return false
}

/// `donutgramIsPreservedBannedChat(transaction:peerId:peer:)` as the UI sees it in a `PeerView`: a banned chat that is
/// still in the chat list. `updatePeersCustom` takes every banned chat it does not keep out of the list in the same
/// transaction, so the peer and the list position of one view answer it without the item cache, and never disagree.
public func donutgramIsPreservedBannedChat(peer: Peer?, groupId: PeerGroupId?) -> Bool {
    return groupId != nil && donutgramPeerIsBanned(peer)
}

/// A local archive keeps the real banned membership, so normal input restrictions still apply.
func donutgramIsPreservedBannedChat(transaction: Transaction, peerId: PeerId, peer: Peer? = nil) -> Bool {
    guard donutgramPeerIsBanned(peer ?? transaction.getPeer(peerId)),
          transaction.getPeerChatListInclusion(peerId) != .notIncluded else {
        return false
    }
    return transaction.retrieveItemCacheEntry(id: donutgramBannedChatCacheId(peerId))?.get(DonutgramBannedChat.self)?.saved == true
}

func donutgramUpdateBannedChat(transaction: Transaction, previous: Peer?, updated: Peer) {
    guard updated is TelegramGroup || updated is TelegramChannel else { return }
    let cacheId = donutgramBannedChatCacheId(updated.id)
    if !donutgramPeerIsBanned(updated) {
        if transaction.retrieveItemCacheEntry(id: cacheId) != nil {
            transaction.removeItemCacheEntry(id: cacheId)
            // Membership was restored: allow normal history synchronization again.
            transaction.addHole(peerId: updated.id, threadId: nil, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... (Int32.max - 1))
            for threadId in transaction.setMessageHistoryThreads(peerId: updated.id) {
                transaction.addHole(peerId: updated.id, threadId: threadId, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... (Int32.max - 1))
            }
        }
        return
    }

    let wasMember: Bool
    if let group = previous as? TelegramGroup {
        wasMember = group.membership == .Member
    } else if let channel = previous as? TelegramChannel {
        wasMember = channel.participationStatus == .member
    } else {
        wasMember = false
    }
    if DGSimpleSettings.shared.keepBannedChats, wasMember,
       transaction.getPeerChatListInclusion(updated.id) != .notIncluded,
       let entry = CodableEntry(DonutgramBannedChat(saved: true)) {
        transaction.putItemCacheEntry(id: cacheId, entry: entry)
    }
    if donutgramIsPreservedBannedChat(transaction: transaction, peerId: updated.id, peer: updated) {
        // Do not leave a loading hole where the server can no longer supply history.
        transaction.removeHole(peerId: updated.id, threadId: nil, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... (Int32.max - 1))
        for threadId in transaction.setMessageHistoryThreads(peerId: updated.id) {
            transaction.removeHole(peerId: updated.id, threadId: threadId, namespace: Namespaces.Message.Cloud, space: .everywhere, range: 1 ... (Int32.max - 1))
        }
    }
}
