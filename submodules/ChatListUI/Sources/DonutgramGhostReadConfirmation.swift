import Foundation
import SwiftSignalKit
import Display
import TelegramCore
import AccountContext
import PresentationDataUtils
import DGSimpleSettings

// Donutgram: ghost mode keeps chats unread on the server, but «Прочитано» and
// «Прочитать все» in the chat list are explicit requests to read there. They
// can't stay local (the server's read state would win again on the next sync),
// so in ghost mode they ask before sending the read receipts.

public func donutgramGhostHidesReadReceipts() -> Bool {
    let settings = DGSimpleSettings.shared
    return settings.ghostModeEnabled && !settings.ghostReadMessages
}

/// Calls `proceed` right away outside ghost mode, otherwise after the user agrees.
public func donutgramConfirmReadInGhostMode(context: AccountContext, present: @escaping (ViewController) -> Void, proceed: @escaping () -> Void, cancel: @escaping () -> Void = {}) {
    guard donutgramGhostHidesReadReceipts() else {
        proceed()
        return
    }
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let languageCode = presentationData.strings.primaryComponent.languageCode
    present(textAlertController(context: context, title: dgLocalized("Режим призрака", languageCode: languageCode), text: dgLocalized("Отправители увидят, что сообщения прочитаны.", languageCode: languageCode), actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: cancel),
        TextAlertAction(type: .defaultAction, title: dgLocalized("Прочитать", languageCode: languageCode), action: proceed)
    ], dismissOnOutsideTap: false))
}

/// The same for a «Прочитано»/«Непрочитано» toggle: it asks only when the toggle
/// reads, that is when the chat (or the topic, with `threadId`) is unread.
public func donutgramConfirmToggleUnreadInGhostMode(context: AccountContext, peerId: EnginePeer.Id, threadId: Int64?, present: @escaping (ViewController) -> Void, proceed: @escaping () -> Void, cancel: @escaping () -> Void = {}) {
    guard donutgramGhostHidesReadReceipts() else {
        proceed()
        return
    }
    let isUnreadSignal: Signal<Bool, NoError>
    if let threadId {
        isUnreadSignal = context.engine.data.get(TelegramEngine.EngineData.Item.Messages.ThreadInfo(peerId: peerId, threadId: threadId))
        |> map { data -> Bool in
            guard let data else {
                return false
            }
            return data.incomingUnreadCount != 0 || data.isMarkedUnread
        }
    } else {
        isUnreadSignal = context.engine.data.get(TelegramEngine.EngineData.Item.Messages.PeerReadCounters(id: peerId))
        |> map { counters -> Bool in
            return counters.isUnread
        }
    }
    let _ = (isUnreadSignal
    |> deliverOnMainQueue).startStandalone(next: { isUnread in
        if isUnread {
            donutgramConfirmReadInGhostMode(context: context, present: present, proceed: proceed, cancel: cancel)
        } else {
            proceed()
        }
    })
}
