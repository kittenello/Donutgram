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

/// Chats read only on this device, ghost mode reads included.
func donutgramGhostLocalReadPeerIds(accountPeerId: PeerId) -> [PeerId] {
    return DGSimpleSettings.shared.ghostLocalReads(accountPeerId: accountPeerId.toInt64()).keys.map { PeerId($0) }
}

/// Runs `body`, which changes the local reads of many chats, and stores them once.
func donutgramBatchGhostLocalReads<T>(accountPeerId: PeerId, _ body: () -> T) -> T {
    return DGSimpleSettings.shared.batchGhostLocalReads(accountPeerId: accountPeerId.toInt64(), body)
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
    if case .Push? = transaction.getPeerReadStateSynchronizationOperation(peerId) {
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
    var read = DGSimpleSettings.GhostLocalRead(maxIncomingReadId: previousMaxIncomingReadId, serverMaxIncomingReadId: previousMaxIncomingReadId, serverMarkedUnread: previousMarkedUnread, readsServerMark: false, readCount: 0)
    if let current = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId), current.maxIncomingReadId == previousMaxIncomingReadId {
        read = current
    }
    read.maxIncomingReadId = maxIncomingReadId
    let newlyReadCount = max(0, previousCount - count)
    read.readCount = read.readCount.map { $0 + newlyReadCount }
    // These become unread again when ghost mode is turned off.
    read.readCountAfterExplicit = read.readCountAfterExplicit.map { $0 + newlyReadCount }
    if previousMarkedUnread {
        // The mark shown here is the server's one.
        read.serverMarkedUnread = true
        read.readsServerMark = true
    }
    donutgramSetGhostLocalRead(read, accountPeerId: accountPeerId, peerId: peerId)
    return true
}

/// Forgets the chat's local read and brings the chat back to the server's read state.
/// Returns false when that state isn't known exactly: the chat needs a validation.
@discardableResult
private func donutgramRestoreServerReadState(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId, read: DGSimpleSettings.GhostLocalRead) -> Bool {
    donutgramSetGhostLocalRead(nil, accountPeerId: accountPeerId, peerId: peerId)
    // A state that is no longer the local read was set from the server in a way that keeps no
    // local read: it is the server's one already.
    guard case let .idBased(maxIncomingReadId, maxOutgoingReadId, maxKnownId, count, _)? = donutgramCloudReadState(transaction: transaction, peerId: peerId), maxIncomingReadId == read.maxIncomingReadId else {
        return true
    }
    transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: read.serverMaxIncomingReadId, maxOutgoingReadId: maxOutgoingReadId, maxKnownId: maxKnownId, count: count + (read.readCount ?? 0), markedUnread: read.serverMarkedUnread)]])
    return read.readCount != nil
}

/// Call before an explicit read of the chat, one the user asked to send. The chat gets the
/// server's read state back first, so the read that follows pushes all it reads.
func donutgramGhostLocalReadWillReadOnServer(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId) {
    guard let read = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId) else {
        return
    }
    if !donutgramRestoreServerReadState(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId, read: read) {
        transaction.setNeedsIncomingReadStateSynchronization(peerId)
    }
}

/// «Отметить как непрочитанное» for a chat read only here: the chat gets the server's read
/// state back, and if that is unread already, the server isn't told anything (marking it
/// unread there would also push the read). Returns false when the chat still has to be
/// marked unread as usual.
func donutgramGhostLocalReadMarkUnread(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId) -> Bool {
    guard let read = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId) else {
        return false
    }
    if !donutgramRestoreServerReadState(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId, read: read) {
        transaction.setNeedsIncomingReadStateSynchronization(peerId)
    }
    if let state = donutgramCloudReadState(transaction: transaction, peerId: peerId), state.isUnread {
        return true
    }
    return false
}

/// Read receipts are no longer hidden: the chats read only here take the server's read state
/// and become unread again.
func donutgramRestoreGhostLocalReads(transaction: Transaction, accountPeerId: PeerId) {
    donutgramBatchGhostLocalReads(accountPeerId: accountPeerId) {
        for (peerId, read) in DGSimpleSettings.shared.ghostLocalReads(accountPeerId: accountPeerId.toInt64()) {
            let peerId = PeerId(peerId)
            if let explicitMaxIncomingReadId = read.explicitMaxIncomingReadId {
                // The explicit read stays; what ghost mode read after it becomes unread again.
                if read.maxIncomingReadId > explicitMaxIncomingReadId {
                    donutgramRestoreExplicitLocalRead(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId, read: read, explicitMaxIncomingReadId: explicitMaxIncomingReadId)
                }
                continue
            }
            // A chat that left the chat list may have no dialog on the server, and its
            // validation would keep retrying.
            if !donutgramRestoreServerReadState(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId, read: read) && transaction.getPeerChatListIndex(peerId) != nil {
                transaction.setNeedsIncomingReadStateSynchronization(peerId)
            }
        }
    }
}

/// The server read the chat up to `messageId` (another device, or a read this device sent).
func donutgramGhostLocalReadDidReadOnServer(accountPeerId: PeerId, messageId: MessageId) {
    guard messageId.namespace == Namespaces.Message.Cloud, var read = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: messageId.peerId) else {
        return
    }
    if messageId.id >= read.maxIncomingReadId {
        donutgramSetGhostLocalRead(nil, accountPeerId: accountPeerId, peerId: messageId.peerId)
    } else if messageId.id > read.serverMaxIncomingReadId {
        // Part of what was read here: the server's count went down by a number of messages
        // not known here, until the next read state from the server.
        read.serverMaxIncomingReadId = messageId.id
        read.serverMarkedUnread = false
        read.readsServerMark = false
        read.readCount = nil
        if let explicitMaxIncomingReadId = read.explicitMaxIncomingReadId, messageId.id >= explicitMaxIncomingReadId {
            // The server has the explicit part: only what ghost mode read is left here.
            read.explicitMaxIncomingReadId = nil
            read.readCountAfterExplicit = nil
        }
        donutgramSetGhostLocalRead(read, accountPeerId: accountPeerId, peerId: messageId.peerId)
    }
}

/// The chat was marked unread, or no longer, on the server: on another device, or by this one
/// (`markDialogUnread`). The local state shows that mark.
func donutgramGhostLocalReadDidUpdateServerUnreadMark(accountPeerId: PeerId, peerId: PeerId, namespace: MessageId.Namespace, value: Bool) {
    guard namespace == Namespaces.Message.Cloud, var read = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId) else {
        return
    }
    read.serverMarkedUnread = value
    read.readsServerMark = false
    donutgramSetGhostLocalRead(read, accountPeerId: accountPeerId, peerId: peerId)
}

/// The chat's unread count here, taken before a read state from the server replaces it.
/// Postbox keeps it up to date with new and deleted messages after the local read.
func donutgramGhostLocalReadCount(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId) -> Int32? {
    guard let read = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId), case let .idBased(maxIncomingReadId, _, _, count, _)? = donutgramCloudReadState(transaction: transaction, peerId: peerId), maxIncomingReadId == read.maxIncomingReadId else {
        return nil
    }
    return count
}

/// Call after the chat's read state was set from the server (`serverMarkedUnread` is nil when
/// the server didn't send the mark), with `localCount` taken before
/// (donutgramGhostLocalReadCount). A chat read only here gets its local read back on top of it.
func donutgramGhostLocalReadDidApplyServerState(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId, serverMaxIncomingReadId: Int32, serverCount: Int32, serverMarkedUnread: Bool?, localCount: Int32?) {
    guard let read = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId) else {
        return
    }
    guard case let .idBased(currentMaxIncomingReadId, maxOutgoingReadId, maxKnownId, _, currentMarkedUnread)? = donutgramCloudReadState(transaction: transaction, peerId: peerId) else {
        donutgramSetGhostLocalRead(nil, accountPeerId: accountPeerId, peerId: peerId)
        return
    }
    let serverMarkedUnread = serverMarkedUnread ?? read.serverMarkedUnread
    // A mark the server got after the local read is shown.
    let readsServerMark = serverMarkedUnread && read.serverMarkedUnread && read.readsServerMark
    let isCovered = !readsServerMark && (serverCount == 0 || serverMaxIncomingReadId >= read.maxIncomingReadId)
    // The server has read the explicit part: what is left was read by ghost mode only. An explicit
    // read of a chat that was only marked unread ends where the server's read does: its part is the mark.
    var explicitMaxIncomingReadId = read.explicitMaxIncomingReadId
    if let value = explicitMaxIncomingReadId, serverMaxIncomingReadId > value || (serverMaxIncomingReadId == value && !readsServerMark) {
        explicitMaxIncomingReadId = nil
    }
    if isCovered || (explicitMaxIncomingReadId == nil && !donutgramGhostModeBlocksContentReads()) {
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
    var count: Int32
    if serverMaxIncomingReadId >= read.maxIncomingReadId {
        // Only the server's unread mark is read here.
        maxIncomingReadId = serverMaxIncomingReadId
        count = serverCount
    } else {
        maxIncomingReadId = read.maxIncomingReadId
        let readCount = serverMaxIncomingReadId == read.serverMaxIncomingReadId ? read.readCount : nil
        if let localCount {
            count = localCount
            if let readCount {
                // The server may have messages this device hasn't got yet.
                count = max(count, serverCount - readCount)
            }
        } else if let readCount {
            count = serverCount - readCount
        } else {
            // Count the messages here; with gaps in them this counts too many.
            transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: serverMaxIncomingReadId, maxOutgoingReadId: maxOutgoingReadId, maxKnownId: maxKnownId, count: serverCount, markedUnread: false)]])
            transaction.applyIncomingReadMaxId(MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: read.maxIncomingReadId))
            if case let .idBased(_, _, _, updatedCount, _)? = donutgramCloudReadState(transaction: transaction, peerId: peerId) {
                count = updatedCount
            } else {
                count = serverCount
            }
        }
        count = max(0, min(count, serverCount))
    }
    donutgramSetGhostLocalRead(DGSimpleSettings.GhostLocalRead(maxIncomingReadId: maxIncomingReadId, serverMaxIncomingReadId: serverMaxIncomingReadId, serverMarkedUnread: serverMarkedUnread, readsServerMark: readsServerMark, readCount: serverCount - count, explicitMaxIncomingReadId: explicitMaxIncomingReadId, readCountAfterExplicit: explicitMaxIncomingReadId == nil ? nil : read.readCountAfterExplicit), accountPeerId: accountPeerId, peerId: peerId)
    // This is the server's state with the local read on top: there is nothing left to sync
    // (resetIncomingReadStates drops the pending synchronization), and a validation would
    // only end up here again.
    transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: maxIncomingReadId, maxOutgoingReadId: maxOutgoingReadId, maxKnownId: max(maxKnownId, maxIncomingReadId), count: count, markedUnread: serverMarkedUnread && !readsServerMark)]])
}

/// `transaction.resetIncomingReadStates` for read states that come from the server.
func donutgramResetIncomingReadStates(transaction: Transaction, accountPeerId: PeerId, _ states: [PeerId: [MessageId.Namespace: PeerReadState]]) {
    guard DGSimpleSettings.shared.hasGhostLocalReads(accountPeerId: accountPeerId.toInt64()) else {
        transaction.resetIncomingReadStates(states)
        return
    }
    var localCounts: [PeerId: Int32] = [:]
    for peerId in states.keys {
        localCounts[peerId] = donutgramGhostLocalReadCount(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId)
    }
    transaction.resetIncomingReadStates(states)
    donutgramBatchGhostLocalReads(accountPeerId: accountPeerId) {
        for (peerId, namespaces) in states {
            if case let .idBased(maxIncomingReadId, _, _, count, markedUnread)? = namespaces[Namespaces.Message.Cloud] {
                donutgramGhostLocalReadDidApplyServerState(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId, serverMaxIncomingReadId: maxIncomingReadId, serverCount: count, serverMarkedUnread: markedUnread, localCount: localCounts[peerId])
            }
        }
    }
}

/// Chats read only here, as they were before «Прочитать все» brought them back to the server's
/// read state.
struct DonutgramGhostLocalReadsBeforeReadAll {
    fileprivate var chats: [PeerId: (read: DGSimpleSettings.GhostLocalRead, state: PeerReadState, needsValidation: Bool)] = [:]
}

/// «Прочитать все» reads the chats that look unread here. Chats read only here look read, so
/// they get the server's read state back first; those that end up outside the read chats get
/// their local read back afterwards.
func donutgramGhostLocalReadsPrepareReadAll(transaction: Transaction, accountPeerId: PeerId) -> DonutgramGhostLocalReadsBeforeReadAll {
    var result = DonutgramGhostLocalReadsBeforeReadAll()
    donutgramBatchGhostLocalReads(accountPeerId: accountPeerId) {
        for (peerId, read) in DGSimpleSettings.shared.ghostLocalReads(accountPeerId: accountPeerId.toInt64()) {
            let peerId = PeerId(peerId)
            guard let state = donutgramCloudReadState(transaction: transaction, peerId: peerId) else {
                continue
            }
            var needsValidation = false
            if case .Validate? = transaction.getPeerReadStateSynchronizationOperation(peerId) {
                needsValidation = true
            }
            result.chats[peerId] = (read, state, needsValidation)
            // Read chats push their state, the others get it back in donutgramGhostLocalReadsFinishReadAll.
            donutgramRestoreServerReadState(transaction: transaction, accountPeerId: accountPeerId, peerId: peerId, read: read)
        }
    }
    return result
}

func donutgramGhostLocalReadsFinishReadAll(transaction: Transaction, accountPeerId: PeerId, before: DonutgramGhostLocalReadsBeforeReadAll, readPeerIds: Set<PeerId>) {
    donutgramBatchGhostLocalReads(accountPeerId: accountPeerId) {
        for (peerId, chat) in before.chats where !readPeerIds.contains(peerId) {
            transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: chat.state]])
            // The reset dropped a validation the chat was waiting for.
            if chat.needsValidation {
                transaction.setNeedsIncomingReadStateSynchronization(peerId)
            }
            donutgramSetGhostLocalRead(chat.read, accountPeerId: accountPeerId, peerId: peerId)
        }
    }
}

/// Ghost mode is off: the chat is read here up to the explicit read only, and what ghost mode read
/// after it is unread again.
private func donutgramRestoreExplicitLocalRead(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId, read: DGSimpleSettings.GhostLocalRead, explicitMaxIncomingReadId: Int32) {
    // A state that is no longer the local read was set from the server in a way that keeps no local
    // read: it is the server's one already.
    guard case let .idBased(maxIncomingReadId, maxOutgoingReadId, maxKnownId, count, markedUnread)? = donutgramCloudReadState(transaction: transaction, peerId: peerId), maxIncomingReadId == read.maxIncomingReadId else {
        donutgramSetGhostLocalRead(nil, accountPeerId: accountPeerId, peerId: peerId)
        return
    }
    var restored = read
    guard let readCountAfterExplicit = read.readCountAfterExplicit else {
        // How many messages ghost mode read is not known: the whole read stays rather than a guess.
        restored.explicitMaxIncomingReadId = read.maxIncomingReadId
        restored.readCountAfterExplicit = 0
        donutgramSetGhostLocalRead(restored, accountPeerId: accountPeerId, peerId: peerId)
        return
    }
    // The count is set, not counted by reading the chat again: Postbox counts only the messages it
    // has, and the explicit part of a chat read without opening it is mostly not loaded.
    let hadSynchronization = transaction.getPeerReadStateSynchronizationOperation(peerId) != nil
    transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: explicitMaxIncomingReadId, maxOutgoingReadId: maxOutgoingReadId, maxKnownId: maxKnownId, count: count + readCountAfterExplicit, markedUnread: markedUnread)]])
    // The reset dropped the chat's synchronization; for a chat read here that is a validation.
    if hadSynchronization {
        transaction.setNeedsIncomingReadStateSynchronization(peerId)
    }
    restored.maxIncomingReadId = explicitMaxIncomingReadId
    restored.readCount = read.readCount.map { max(0, $0 - readCountAfterExplicit) }
    restored.readCountAfterExplicit = 0
    donutgramSetGhostLocalRead(restored, accountPeerId: accountPeerId, peerId: peerId)
}

/// Explicit local read, independent of ghost mode. Keep the server baseline and do
/// not create a Push operation, including when messages have holes in local history.
/// Returns the id the chat is read up to, or nil for a chat that can't be read this way.
@discardableResult
func donutgramReadChatLocally(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId) -> Int32? {
    guard donutgramIsGhostLocalReadPeer(peerId), let peer = transaction.getPeer(peerId), !peer.isForumOrMonoForum,
          transaction.getPeerChatListIndex(peerId) != nil,
          case let .idBased(maxIncomingReadId, maxOutgoingReadId, maxKnownId, count, markedUnread)? = donutgramCloudReadState(transaction: transaction, peerId: peerId) else {
        return nil
    }
    // A previously requested server read owns this state until it completes.
    let synchronizationOperation = transaction.getPeerReadStateSynchronizationOperation(peerId)
    if case .Push? = synchronizationOperation { return nil }
    let topId = transaction.getTopPeerMessageIndex(peerId: peerId, namespace: Namespaces.Message.Cloud)?.id.id ?? maxKnownId
    let readId = max(maxIncomingReadId, max(maxKnownId, topId))
    // A recorded read the chat's state no longer has was replaced by the server's state.
    var read = DGSimpleSettings.GhostLocalRead(maxIncomingReadId: maxIncomingReadId, serverMaxIncomingReadId: maxIncomingReadId, serverMarkedUnread: markedUnread, readsServerMark: false, readCount: 0)
    if let current = donutgramGhostLocalReadState(accountPeerId: accountPeerId, peerId: peerId), current.maxIncomingReadId == maxIncomingReadId {
        read = current
    }
    read.maxIncomingReadId = readId
    read.readCount = read.readCount.map { $0 + count }
    read.explicitMaxIncomingReadId = readId
    read.readCountAfterExplicit = 0
    if markedUnread {
        read.serverMarkedUnread = true
        read.readsServerMark = true
    }
    donutgramSetGhostLocalRead(read, accountPeerId: accountPeerId, peerId: peerId)
    transaction.resetIncomingReadStates([peerId: [Namespaces.Message.Cloud: .idBased(maxIncomingReadId: readId, maxOutgoingReadId: maxOutgoingReadId, maxKnownId: readId, count: 0, markedUnread: false)]])
    // The reset dropped a validation the chat was waiting for; it applies the local read on top.
    if case .Validate? = synchronizationOperation {
        transaction.setNeedsIncomingReadStateSynchronization(peerId)
    }
    return readId
}
