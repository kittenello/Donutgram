import Foundation
import Postbox
import DGSimpleSettings

// Ghost mode with hidden read receipts reads chats on this device only: opening a chat
// marks its messages read here, while the server (and so the senders) still has them
// unread. Each such chat is recorded per account in DGSimpleSettings together with the
// server's read state the local read was made on top of, so that:
// - the read is never pushed to the server (pushPeerReadState validates instead);
// - a read state that comes from the server gets the local read applied on top of it
//   again, with the unread count kept right, instead of making the chat unread again;
// - an explicit read («Прочитано», «Прочитать все», reading on reply), «Отметить как
//   непрочитанное» and read receipts that are no longer hidden first bring the chat back to
//   the server's state.
// Only regular cloud chats from the chat list are read locally; secret chats, forum
// topics and channel direct messages stay unread, as before.

private func donutgramIsGhostLocalReadPeer(_ peerId: PeerId) -> Bool {
    return peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup || peerId.namespace == Namespaces.Peer.CloudChannel
}

private func donutgramCloudReadState(transaction: Transaction, peerId: PeerId) -> PeerReadState? {
    return transaction.getPeerReadStates(peerId)?.first(where: { $0.0 == Namespaces.Message.Cloud })?.1
}

private func donutgramSetGhostLocalRead(_ read: DGSimpleSettings.GhostLocalRead?, accountPeerId: PeerId, peerId: PeerId) {
    DGSimpleSettings.shared.setGhostLocalRead(read, accountPeerId: accountPeerId.toInt64(), peerId: peerId.toInt64())
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
    // A read waiting to be sent (one made before) sends the chat's state as it is when it
    // goes out, and would take this read along. The chat is read here once it is sent.
    guard !transaction.hasPendingIncomingReadStatePush(peerId) else {
        return false
    }
    guard let previousState = donutgramCloudReadState(transaction: transaction, peerId: peerId), case let .idBased(previousMaxIncomingReadId, _, _, previousCount, previousMarkedUnread) = previousState else {
        return false
    }
    // A chat marked unread is read from its current read id, never back from it.
    transaction.applyIncomingReadMaxId(MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: max(index.id.id, previousMaxIncomingReadId)))
    guard let updatedState = donutgramCloudReadState(transaction: transaction, peerId: peerId), updatedState != previousState, case let .idBased(maxIncomingReadId, _, _, count, _) = updatedState else {
        return true
    }
    // Without a recorded read, or with one the chat's state no longer has (it was set from the
    // server in a way that keeps no local read), the chat's state is the server's one.
    var read = DGSimpleSettings.GhostLocalRead(maxIncomingReadId: previousMaxIncomingReadId, serverMaxIncomingReadId: previousMaxIncomingReadId, serverMarkedUnread: previousMarkedUnread, readCount: 0)
    if let current = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId), current.maxIncomingReadId == previousMaxIncomingReadId {
        read = current
    }
    read.maxIncomingReadId = maxIncomingReadId
    read.readCount += max(0, previousCount - count)
    donutgramSetGhostLocalRead(read, accountPeerId: accountPeerId, peerId: peerId)
    return true
}

/// Forgets the chat's local read and brings the chat back to the server's read state.
private func donutgramRestoreServerReadState(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId, read: DGSimpleSettings.GhostLocalRead) {
    donutgramSetGhostLocalRead(nil, accountPeerId: accountPeerId, peerId: peerId)
    // A state that is no longer the local read (set from the server in a way that keeps no
    // local read) stays as it is.
    guard case let .idBased(maxIncomingReadId, maxOutgoingReadId, maxKnownId, count, _)? = donutgramCloudReadState(transaction: transaction, peerId: peerId), maxIncomingReadId == read.maxIncomingReadId else {
        return
    }
    transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: read.serverMaxIncomingReadId, maxOutgoingReadId: maxOutgoingReadId, maxKnownId: maxKnownId, count: count + read.readCount, markedUnread: read.serverMarkedUnread)]])
}

/// Call before an explicit read of the chat, one the user asked to send. The chat gets the
/// server's read state back first, so the read that follows pushes all it reads.
func donutgramGhostLocalReadWillReadOnServer(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId) {
    guard let read = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId) else {
        return
    }
    donutgramRestoreServerReadState(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId, read: read)
    // A read that changes nothing pushes nothing; the chat then takes the server's state.
    transaction.setNeedsIncomingReadStateSynchronization(peerId)
}

/// «Отметить как непрочитанное» for a chat read only here: the chat gets the server's read
/// state back, and if that is unread already, the server isn't told anything (marking it
/// unread there would also push the read). Returns false when the chat still has to be
/// marked unread as usual.
func donutgramGhostLocalReadMarkUnread(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId) -> Bool {
    guard let read = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId) else {
        return false
    }
    donutgramRestoreServerReadState(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId, read: read)
    transaction.setNeedsIncomingReadStateSynchronization(peerId)
    if let state = donutgramCloudReadState(transaction: transaction, peerId: peerId), state.isUnread {
        return true
    }
    return false
}

/// Read receipts are no longer hidden: the chats read only here take the server's read state
/// and become unread again.
func donutgramRestoreGhostLocalReads(transaction: Transaction, accountPeerId: PeerId) {
    for (peerId, read) in DGSimpleSettings.shared.ghostLocalReads(accountPeerId: accountPeerId.toInt64()) {
        let peerId = PeerId(peerId)
        donutgramRestoreServerReadState(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId, read: read)
        // A chat that left the chat list may have no dialog on the server, and its
        // validation would keep retrying.
        if transaction.getPeerChatListIndex(peerId) != nil {
            transaction.setNeedsIncomingReadStateSynchronization(peerId)
        }
    }
}

/// The server read the chat up to `messageId` (another device, or a read this device sent).
func donutgramGhostLocalReadDidReadOnServer(accountPeerId: PeerId, messageId: MessageId) {
    guard messageId.namespace == Namespaces.Message.Cloud, let read = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: messageId.peerId) else {
        return
    }
    // A read that covers only part of the local one changes the server's count by an unknown
    // number of messages; the next read state from the server counts it again
    // (donutgramGhostLocalReadDidApplyServerState).
    if messageId.id >= read.maxIncomingReadId {
        donutgramSetGhostLocalRead(nil, accountPeerId: accountPeerId, peerId: messageId.peerId)
    }
}

/// The chat was marked unread, or no longer, on the server (by another device). The local
/// state shows that mark; the local read keeps it as the server's one.
func donutgramGhostLocalReadDidUpdateServerUnreadMark(accountPeerId: PeerId, peerId: PeerId, namespace: MessageId.Namespace, value: Bool) {
    guard namespace == Namespaces.Message.Cloud, var read = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId) else {
        return
    }
    read.serverMarkedUnread = value
    donutgramSetGhostLocalRead(read, accountPeerId: accountPeerId, peerId: peerId)
}

/// Call after the chat's read state was set from the server (`serverMarkedUnread` is nil when
/// the server didn't send the mark). A chat read only here gets its local read back on top
/// of it.
func donutgramGhostLocalReadDidApplyServerState(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId, serverMaxIncomingReadId: Int32, serverCount: Int32, serverMarkedUnread: Bool?) {
    guard let read = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId) else {
        return
    }
    guard case let .idBased(currentMaxIncomingReadId, maxOutgoingReadId, maxKnownId, _, currentMarkedUnread)? = donutgramCloudReadState(transaction: transaction, peerId: peerId) else {
        donutgramSetGhostLocalRead(nil, accountPeerId: accountPeerId, peerId: peerId)
        return
    }
    let serverMarkedUnread = serverMarkedUnread ?? read.serverMarkedUnread
    let isCovered = !serverMarkedUnread && (serverCount == 0 || serverMaxIncomingReadId >= read.maxIncomingReadId)
    if isCovered || !donutgramGhostModeBlocksContentReads() {
        // The server has read what was read here, or read receipts are no longer hidden:
        // the server's state stays. Some server updates keep the higher of the local and the
        // server id together with the server's count; the server's id goes with that count.
        donutgramSetGhostLocalRead(nil, accountPeerId: accountPeerId, peerId: peerId)
        if currentMaxIncomingReadId > serverMaxIncomingReadId {
            transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: serverMaxIncomingReadId, maxOutgoingReadId: maxOutgoingReadId, maxKnownId: maxKnownId, count: serverCount, markedUnread: currentMarkedUnread)]])
        }
        return
    }
    let maxIncomingReadId: Int32
    let count: Int32
    if serverMaxIncomingReadId >= read.maxIncomingReadId {
        // Marked unread on the server only.
        maxIncomingReadId = serverMaxIncomingReadId
        count = serverCount
    } else if serverMaxIncomingReadId == read.serverMaxIncomingReadId {
        // The messages here may have gaps, so the read ones are taken from the record rather
        // than counted again.
        maxIncomingReadId = read.maxIncomingReadId
        count = max(0, serverCount - read.readCount)
    } else {
        // The server read part of the chat on another device: count the messages here.
        transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: serverMaxIncomingReadId, maxOutgoingReadId: maxOutgoingReadId, maxKnownId: maxKnownId, count: serverCount, markedUnread: false)]])
        transaction.applyIncomingReadMaxId(MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: read.maxIncomingReadId))
        maxIncomingReadId = read.maxIncomingReadId
        if case let .idBased(_, _, _, updatedCount, _)? = donutgramCloudReadState(transaction: transaction, peerId: peerId) {
            count = updatedCount
        } else {
            count = serverCount
        }
    }
    donutgramSetGhostLocalRead(DGSimpleSettings.GhostLocalRead(maxIncomingReadId: maxIncomingReadId, serverMaxIncomingReadId: serverMaxIncomingReadId, serverMarkedUnread: serverMarkedUnread, readCount: max(0, serverCount - count)), accountPeerId: accountPeerId, peerId: peerId)
    // This is the server's state with the local read on top: there is nothing left to sync
    // (resetIncomingReadStates drops the pending synchronization), and a validation would
    // only end up here again.
    transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: maxIncomingReadId, maxOutgoingReadId: maxOutgoingReadId, maxKnownId: max(maxKnownId, maxIncomingReadId), count: count, markedUnread: false)]])
}

/// `transaction.resetIncomingReadStates` for read states that come from the server.
func donutgramResetIncomingReadStates(transaction: Transaction, accountPeerId: PeerId, _ states: [PeerId: [MessageId.Namespace: PeerReadState]]) {
    transaction.resetIncomingReadStates(states)
    guard DGSimpleSettings.shared.hasGhostLocalReads(accountPeerId: accountPeerId.toInt64()) else {
        return
    }
    for (peerId, namespaces) in states {
        if case let .idBased(maxIncomingReadId, _, _, count, markedUnread)? = namespaces[Namespaces.Message.Cloud] {
            donutgramGhostLocalReadDidApplyServerState(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId, serverMaxIncomingReadId: maxIncomingReadId, serverCount: count, serverMarkedUnread: markedUnread)
        }
    }
}

/// «Прочитать все» reads the chats that look unread here. Chats read only here look read, so
/// they get the server's read state back first; those that end up outside the read chats get
/// their local read back afterwards.
func donutgramGhostLocalReadsPrepareReadAll(transaction: Transaction, accountPeerId: PeerId) -> [PeerId: (DGSimpleSettings.GhostLocalRead, PeerReadState)] {
    var restored: [PeerId: (DGSimpleSettings.GhostLocalRead, PeerReadState)] = [:]
    for (peerId, read) in DGSimpleSettings.shared.ghostLocalReads(accountPeerId: accountPeerId.toInt64()) {
        let peerId = PeerId(peerId)
        guard let state = donutgramCloudReadState(transaction: transaction, peerId: peerId) else {
            continue
        }
        restored[peerId] = (read, state)
        donutgramRestoreServerReadState(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId, read: read)
    }
    return restored
}

func donutgramGhostLocalReadsFinishReadAll(transaction: Transaction, accountPeerId: PeerId, restored: [PeerId: (DGSimpleSettings.GhostLocalRead, PeerReadState)], readPeerIds: Set<PeerId>) {
    for (peerId, (read, state)) in restored where !readPeerIds.contains(peerId) {
        transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: state]])
        donutgramSetGhostLocalRead(read, accountPeerId: accountPeerId, peerId: peerId)
    }
}
