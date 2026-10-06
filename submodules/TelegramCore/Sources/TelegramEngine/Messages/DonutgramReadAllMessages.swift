import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi
import MtProtoKit

/// Explicit user action: read cloud dialogs on the server even when ghost mode suppresses automatic receipts.
/// Enumerate both folders from the server, including dialogs that have never been loaded into Postbox.
func _internal_donutgramReadAllMessages(postbox: Postbox, network: Network, stateManager: AccountStateManager) -> Signal<Bool, NoError> {
    return donutgramReadDialogPage(postbox: postbox, network: network, stateManager: stateManager, folderId: 0)
    |> mapToSignal { mainSucceeded in
        donutgramReadDialogPage(postbox: postbox, network: network, stateManager: stateManager, folderId: 1)
        |> map { archiveSucceeded in mainSucceeded && archiveSucceeded }
    }
}

private func donutgramReadDialogPage(postbox: Postbox, network: Network, stateManager: AccountStateManager, folderId: Int32, offsetDate: Int32 = 0, offsetId: Int32 = 0, offsetPeer: Api.InputPeer = .inputPeerEmpty, offsetPeerId: PeerId? = nil) -> Signal<Bool, NoError> {
    let flags: Int32 = (1 << 1) | (offsetId == 0 ? 0 : (1 << 0))
    return network.request(Api.functions.messages.getDialogs(flags: flags, folderId: folderId, offsetDate: offsetDate, offsetId: offsetId, offsetPeer: offsetPeer, limit: 100, hash: 0))
    |> map(Optional.init)
    |> `catch` { _ in .single(nil) }
    |> mapToSignal { result -> Signal<Bool, NoError> in
        guard let result else { return .single(false) }
        let dialogs: [Api.Dialog]
        let messages: [Api.Message]
        let peers: AccumulatedPeers
        let hasMore: Bool
        switch result {
        case let .dialogs(data):
            dialogs = data.dialogs
            messages = data.messages
            peers = AccumulatedPeers(chats: data.chats, users: data.users)
            hasMore = false
        case let .dialogsSlice(data):
            dialogs = data.dialogs
            messages = data.messages
            peers = AccumulatedPeers(chats: data.chats, users: data.users)
            hasMore = !dialogs.isEmpty
        case .dialogsNotModified:
            return .single(false)
        }

        var readSignals: [Signal<Bool, NoError>] = []
        var nextOffset: (date: Int32, id: Int32, peer: Api.InputPeer, peerId: PeerId)?
        for dialog in dialogs {
            guard case let .dialog(data) = dialog else { continue }
            let peerId = data.peer.peerId
            guard let peer = peers.get(peerId), let inputPeer = apiInputPeer(peer) else {
                if data.unreadCount > 0 || data.flags & (1 << 3) != 0 { readSignals.append(.single(false)) }
                continue
            }
            if data.flags & (1 << 2) == 0,
               let message = messages.first(where: { $0.peerId == peerId && $0.rawId == data.topMessage }),
               let timestamp = message.timestamp {
                nextOffset = (timestamp, data.topMessage, inputPeer, peerId)
            }
            let markedUnread = data.flags & (1 << 3) != 0
            let needsReadHistory = data.unreadCount > 0 || data.readInboxMaxId < data.topMessage
            guard needsReadHistory || markedUnread else { continue }
            let readHistory: Signal<Bool, NoError>
            if !needsReadHistory {
                // A manually marked dialog with no unread messages only needs markDialogUnread.
                readHistory = .single(true)
            } else if let inputChannel = apiInputChannel(peer) {
                readHistory = network.request(Api.functions.channels.readHistory(channel: inputChannel, maxId: data.topMessage))
                |> map { result in if case .boolTrue = result { return true }; return false }
                |> `catch` { _ in .single(false) }
            } else {
                readHistory = network.request(Api.functions.messages.readHistory(peer: inputPeer, maxId: data.topMessage))
                |> map { result -> Bool in
                    if case let .affectedMessages(data) = result {
                        stateManager.addUpdateGroups([.updatePts(pts: data.pts, ptsCount: data.ptsCount)])
                    }
                    return true
                }
                |> `catch` { _ in .single(false) }
            }
            let clearUnreadMark: Signal<Bool, NoError>
            if markedUnread {
                clearUnreadMark = network.request(Api.functions.messages.markDialogUnread(flags: 0, parentPeer: nil, peer: .inputDialogPeer(.init(peer: inputPeer))))
                |> map { result in if case .boolTrue = result { return true }; return false }
                |> `catch` { _ in .single(false) }
            } else {
                clearUnreadMark = .single(true)
            }
            readSignals.append(readHistory |> mapToSignal { readSucceeded in
                clearUnreadMark |> mapToSignal { markSucceeded -> Signal<Bool, NoError> in
                    return postbox.transaction { transaction -> Bool in
                        // Apply only successful server acknowledgements, and never read messages arriving after the snapshot.
                        if needsReadHistory && readSucceeded {
                            let readMessageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: data.topMessage)
                            transaction.applyIncomingReadMaxId(readMessageId)
                            donutgramGhostLocalReadDidReadOnServer(accountPeerId: stateManager.accountPeerId, messageId: readMessageId)
                        }
                        if markSucceeded { transaction.applyMarkUnread(peerId: peerId, namespace: Namespaces.Message.Cloud, value: false, interactive: false) }
                        return readSucceeded && markSucceeded
                    }
                }
            })
        }
        let resultSignal = donutgramReadDialogBatches(readSignals)
        guard hasMore else { return resultSignal }
        guard let nextOffset, nextOffset.id != offsetId || nextOffset.date != offsetDate || nextOffset.peerId != offsetPeerId else {
            return resultSignal |> map { _ in false }
        }
        return resultSignal |> mapToSignal { succeeded in
            donutgramReadDialogPage(postbox: postbox, network: network, stateManager: stateManager, folderId: folderId, offsetDate: nextOffset.date, offsetId: nextOffset.id, offsetPeer: nextOffset.peer, offsetPeerId: nextOffset.peerId)
            |> map { succeeded && $0 }
        }
    }
}

private func donutgramReadDialogBatches(_ signals: [Signal<Bool, NoError>]) -> Signal<Bool, NoError> {
    // Each dialog executes its RPCs sequentially. Run at most four dialogs at once,
    // so large accounts do not wait for a separate round trip for every chat.
    let batchSize = 4
    var result: Signal<Bool, NoError> = .single(true)
    for offset in stride(from: 0, to: signals.count, by: batchSize) {
        let batch = Array(signals[offset ..< min(offset + batchSize, signals.count)])
        let batchResult: Signal<Bool, NoError> = combineLatest(batch)
        |> map { values in values.allSatisfy { $0 } }
        result = result |> mapToSignal { succeeded in
            // A failed dialog must not prevent the remaining batches from being read.
            batchResult |> map { succeeded && $0 }
        }
    }
    return result
}
