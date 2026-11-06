import Foundation
import Postbox
import SwiftSignalKit
import DGSimpleSettings

/// Donutgram-only: between TelegramCore's preference ids (`PreferencesKeyValues`, counting up from 0) and the
/// application-specific ones (`applicationSpecificPreferencesKey`, 1000 and up).
private let donutgramEmptyReplyDraftsPreferencesKey: ValueBoxKey = {
    let key = ValueBoxKey(length: 4)
    key.setInt32(0, value: 500)
    return key
}()

/// The «Скрывать черновик пустого ответа» value this account's saved drafts were last re-sorted for.
private struct DonutgramEmptyReplyDraftsState: Codable {
    let hidingEmptyReplies: Bool
}

/// Keeps saved bare replies where «Скрывать черновик пустого ответа» puts them in the chat list: at once when the
/// switch flips, and at launch when the drafts were last re-sorted for the other value (or never: drafts saved
/// before this pass).
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
            // Every draft saved since the last pass already used its value: a launch with the switch unchanged has
            // nothing to re-sort and does not read every saved chat state.
            if transaction.getPreferencesEntry(key: donutgramEmptyReplyDraftsPreferencesKey)?.get(DonutgramEmptyReplyDraftsState.self)?.hidingEmptyReplies == hidden {
                return
            }
            donutgramRefreshEmptyReplyDraftTimestamps(transaction: transaction, hidingEmptyReplies: hidden)
            transaction.setPreferencesEntry(key: donutgramEmptyReplyDraftsPreferencesKey, value: PreferencesEntry(DonutgramEmptyReplyDraftsState(hidingEmptyReplies: hidden)))
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
