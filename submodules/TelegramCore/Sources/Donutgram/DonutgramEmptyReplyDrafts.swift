import Foundation
import Postbox
import SwiftSignalKit
import DGSimpleSettings

func managedDonutgramEmptyReplyDrafts(postbox: Postbox) -> Signal<Void, NoError> {
    return (Signal<Bool, NoError> { subscriber in
        let settings = DGSimpleSettings.shared
        let observer = NotificationCenter.default.addObserver(forName: DGSimpleSettings.didChangeNotification, object: settings, queue: nil) { _ in
            subscriber.putNext(settings.hideEmptyReplyDrafts)
        }
        subscriber.putNext(settings.hideEmptyReplyDrafts)
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    |> distinctUntilChanged)
    |> mapToSignal { hidden in
        return postbox.transaction { transaction -> Void in
            donutgramRefreshEmptyReplyDraftTimestamps(transaction: transaction, hidingEmptyReplies: hidden)
        }
    }
}

func donutgramRefreshEmptyReplyDraftTimestamps(transaction: Transaction, hidingEmptyReplies: Bool) {
    func updatedState(_ state: StoredPeerChatInterfaceState?) -> StoredPeerChatInterfaceState? {
        guard let state, let decoded = _internal_decodeStoredChatInterfaceState(state: state),
            let input = decoded.synchronizeableInputState, input.isEmptyReply else {
            return nil
        }
        var timestamp = input.chatListTimestamp(hidingEmptyReplies: hidingEmptyReplies)
        if let media = decoded.mediaDraftState {
            timestamp = max(timestamp ?? media.timestamp, media.timestamp)
        }
        guard timestamp != state.overrideChatTimestamp else {
            return nil
        }
        return StoredPeerChatInterfaceState(
            overrideChatTimestamp: timestamp,
            historyScrollMessageIndex: state.historyScrollMessageIndex,
            associatedMessageIds: state.associatedMessageIds,
            data: state.data
        )
    }
    for peerId in transaction.getPeerChatInterfaceStateIds() {
        if let state = updatedState(transaction.getPeerChatInterfaceState(peerId)) {
            transaction.setPeerChatInterfaceState(peerId, state: state)
        }
    }
    for thread in transaction.getPeerChatThreadInterfaceStateIds() {
        if let state = updatedState(transaction.getPeerChatThreadInterfaceState(thread.peerId, threadId: thread.threadId)) {
            transaction.setPeerChatThreadInterfaceState(thread.peerId, threadId: thread.threadId, state: state)
        }
    }
}
