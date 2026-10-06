import Foundation
import Postbox
import DGSimpleSettings

// Ghost mode with hidden read receipts reads chats on this device only: opening a chat
// marks its messages read here, while the server (and so the senders) still has them
// unread. Such chats are recorded per account in DGSimpleSettings, so that:
// - the read is never pushed to the server (synchronizePeerReadState validates instead);
// - a server read state behind the local one neither loops the validation nor makes the
//   chat unread again: the local read is applied on top of it;
// - once read receipts are no longer hidden, the chats take the server's read state and
//   become unread again (managedSynchronizePeerReadStates).
// Explicit reads («Прочитано», «Прочитать все», reading on reply) still go to the server.
// Only regular cloud chats from the chat list are read locally; secret chats, forum
// topics and channel direct messages stay unread, as before.

private func donutgramIsGhostLocalReadPeer(_ peerId: PeerId) -> Bool {
    return peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup || peerId.namespace == Namespaces.Peer.CloudChannel
}

private func donutgramCloudReadState(transaction: Transaction, peerId: PeerId) -> PeerReadState? {
    return transaction.getPeerReadStates(peerId)?.first(where: { $0.0 == Namespaces.Message.Cloud })?.1
}

func donutgramGhostLocalReadState(accountPeerId: PeerId, peerId: PeerId) -> DGSimpleSettings.GhostLocalRead? {
    guard donutgramIsGhostLocalReadPeer(peerId) else {
        return nil
    }
    return DGSimpleSettings.shared.ghostLocalRead(accountPeerId: accountPeerId.toInt64(), peerId: peerId.toInt64())
}

/// Reads the chat up to `index` on this device only. Returns false for chats that can't
/// be read this way: they stay unread.
@discardableResult
func donutgramApplyGhostLocalRead(transaction: Transaction, accountPeerId: PeerId, index: MessageIndex) -> Bool {
    let peerId = index.id.peerId
    guard index.id.namespace == Namespaces.Message.Cloud, donutgramIsGhostLocalReadPeer(peerId) else {
        return false
    }
    guard let peer = transaction.getPeer(peerId), !peer.isForumOrMonoForum else {
        return false
    }
    // A chat outside the chat list (a previewed channel, for example) has no server read
    // state that would bring it back.
    guard transaction.getPeerChatListIndex(peerId) != nil else {
        return false
    }
    guard let previousState = donutgramCloudReadState(transaction: transaction, peerId: peerId), case .idBased = previousState else {
        return false
    }
    transaction.applyIncomingReadMaxId(index.id)
    if let updatedState = donutgramCloudReadState(transaction: transaction, peerId: peerId), updatedState != previousState, case let .idBased(maxIncomingReadId, _, _, _, _) = updatedState {
        DGSimpleSettings.shared.setGhostLocalRead(maxIncomingReadId: maxIncomingReadId, accountPeerId: accountPeerId.toInt64(), peerId: peerId.toInt64())
    }
    return true
}

/// Call before an explicit read of the chat, one the user asked to send. The local state
/// already counts a locally read chat as read, so the read applied next would change
/// nothing and push nothing; marking the chat unread here (locally) makes it push.
func donutgramGhostLocalReadWillReadOnServer(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId) {
    guard donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId) != nil else {
        return
    }
    DGSimpleSettings.shared.removeGhostLocalRead(accountPeerId: accountPeerId.toInt64(), peerId: peerId.toInt64())
    transaction.applyMarkUnread(peerId: peerId, namespace: Namespaces.Message.Cloud, value: true, interactive: false)
}

/// «Отметить как непрочитанное» for a chat read only here: the server still has it unread,
/// so the chat takes the server's read state back instead of telling the server anything
/// (marking it unread there would also push the local read). Returns false for other chats.
func donutgramGhostLocalReadMarkUnread(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId) -> Bool {
    guard let state = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId) else {
        return false
    }
    if case .active = state {
        let _ = DGSimpleSettings.shared.beginRevertingGhostLocalReads(accountPeerId: accountPeerId.toInt64(), peerId: peerId.toInt64())
    }
    // Unread right away; the validation then brings the server's counters.
    transaction.applyMarkUnread(peerId: peerId, namespace: Namespaces.Message.Cloud, value: true, interactive: false)
    transaction.setNeedsIncomingReadStateSynchronization(peerId)
    return true
}

/// The server read the chat up to `messageId` (another device, or a read this device sent).
func donutgramGhostLocalReadDidReadOnServer(accountPeerId: PeerId, messageId: MessageId) {
    guard messageId.namespace == Namespaces.Message.Cloud, case let .active(maxIncomingReadId)? = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: messageId.peerId) else {
        return
    }
    if messageId.id >= maxIncomingReadId {
        DGSimpleSettings.shared.removeGhostLocalRead(accountPeerId: accountPeerId.toInt64(), peerId: messageId.peerId.toInt64())
    }
}

/// Call after the chat's read state was set from the server. A chat read only here gets
/// its local read back on top of it; a reverting chat keeps the server's state.
func donutgramGhostLocalReadDidApplyServerState(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId, serverMaxIncomingReadId: Int32, serverIsRead: Bool) {
    guard let state = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId) else {
        return
    }
    // Some server updates keep the higher of the local and the server id together with the
    // server's unread count; take the server's id back so that the count stays consistent.
    if case let .idBased(maxIncomingReadId, maxOutgoingReadId, maxKnownId, count, markedUnread)? = donutgramCloudReadState(transaction: transaction, peerId: peerId), maxIncomingReadId > serverMaxIncomingReadId {
        transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: serverMaxIncomingReadId, maxOutgoingReadId: maxOutgoingReadId, maxKnownId: maxKnownId, count: count, markedUnread: markedUnread)]])
    }
    switch state {
    case .reverting:
        DGSimpleSettings.shared.removeGhostLocalRead(accountPeerId: accountPeerId.toInt64(), peerId: peerId.toInt64())
    case let .active(maxIncomingReadId):
        if serverIsRead || serverMaxIncomingReadId >= maxIncomingReadId || !donutgramGhostModeBlocksContentReads() {
            DGSimpleSettings.shared.removeGhostLocalRead(accountPeerId: accountPeerId.toInt64(), peerId: peerId.toInt64())
            return
        }
        transaction.applyIncomingReadMaxId(MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: maxIncomingReadId))
        // This is the server's state with the local read on top: there is nothing left to
        // sync, and a validation would only end up here again.
        transaction.confirmSynchronizedIncomingReadState(peerId)
    }
}

/// `transaction.resetIncomingReadStates` for read states that come from the server.
func donutgramResetIncomingReadStates(transaction: Transaction, accountPeerId: PeerId, _ states: [PeerId: [MessageId.Namespace: PeerReadState]]) {
    transaction.resetIncomingReadStates(states)
    guard DGSimpleSettings.shared.hasGhostLocalReads(accountPeerId: accountPeerId.toInt64()) else {
        return
    }
    for (peerId, namespaces) in states {
        if case let .idBased(maxIncomingReadId, _, _, count, markedUnread)? = namespaces[Namespaces.Message.Cloud] {
            donutgramGhostLocalReadDidApplyServerState(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId, serverMaxIncomingReadId: maxIncomingReadId, serverIsRead: count == 0 && !markedUnread)
        }
    }
}

/// «Прочитать все» reads the chats that look unread here. Chats read only here look read,
/// so they are marked unread (locally) first, and those that end up outside the read
/// chats are marked back afterwards.
func donutgramGhostLocalReadsPrepareReadAll(transaction: Transaction, accountPeerId: PeerId) -> [PeerId] {
    var marked: [PeerId] = []
    for (peerId, _) in DGSimpleSettings.shared.activeGhostLocalReads(accountPeerId: accountPeerId.toInt64()) {
        let peerId = PeerId(peerId)
        if case let .idBased(_, _, _, _, markedUnread)? = donutgramCloudReadState(transaction: transaction, peerId: peerId), !markedUnread {
            transaction.applyMarkUnread(peerId: peerId, namespace: Namespaces.Message.Cloud, value: true, interactive: false)
            marked.append(peerId)
        }
    }
    return marked
}

func donutgramGhostLocalReadsFinishReadAll(transaction: Transaction, accountPeerId: PeerId, markedPeerIds: [PeerId], readPeerIds: Set<PeerId>) {
    for peerId in markedPeerIds where !readPeerIds.contains(peerId) {
        transaction.applyMarkUnread(peerId: peerId, namespace: Namespaces.Message.Cloud, value: false, interactive: false)
    }
}
