import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import ItemListUI
import ItemListPeerItem
import LocalizedPeerData
import PresentationDataUtils
import DGSimpleSettings

private final class DGSavedDeletedArguments {
    let context: AccountContext
    let deleteAll: () -> Void
    let deleteChat: (EnginePeer) -> Void
    let openChat: (EnginePeer) -> Void
    let setPeerIdWithRevealedOptions: (EnginePeer.Id?, EnginePeer.Id?) -> Void

    init(context: AccountContext, deleteAll: @escaping () -> Void, deleteChat: @escaping (EnginePeer) -> Void, openChat: @escaping (EnginePeer) -> Void, setPeerIdWithRevealedOptions: @escaping (EnginePeer.Id?, EnginePeer.Id?) -> Void) {
        self.context = context
        self.deleteAll = deleteAll
        self.deleteChat = deleteChat
        self.openChat = openChat
        self.setPeerIdWithRevealedOptions = setPeerIdWithRevealedOptions
    }
}

private enum DGSavedDeletedSection: Int32 {
    case usage
    case delete
    case chats
}

private enum DGSavedDeletedEntryId: Hashable {
    case usageHeader
    case messages
    case files
    case deleteAll
    case deleteInfo
    case chatsHeader
    case chat(EnginePeer.Id)
}

private enum DGSavedDeletedEntry: ItemListNodeEntry {
    case usageHeader(String)
    // A title and its value; the value is «…» until the first count finishes.
    case messages(String, String)
    case files(String, String)
    // The title and whether there is anything to delete now.
    case deleteAll(String, Bool)
    case deleteInfo(String)
    case chatsHeader(String)
    // The chat, its subtitle, the edit state of its row and whether it can be deleted now.
    case chat(Int32, EnginePeer, String, ItemListPeerItemEditing, Bool)

    var section: ItemListSectionId {
        switch self {
        case .usageHeader, .messages, .files:
            return DGSavedDeletedSection.usage.rawValue
        case .deleteAll, .deleteInfo:
            return DGSavedDeletedSection.delete.rawValue
        case .chatsHeader, .chat:
            return DGSavedDeletedSection.chats.rawValue
        }
    }

    var stableId: DGSavedDeletedEntryId {
        switch self {
        case .usageHeader:
            return .usageHeader
        case .messages:
            return .messages
        case .files:
            return .files
        case .deleteAll:
            return .deleteAll
        case .deleteInfo:
            return .deleteInfo
        case .chatsHeader:
            return .chatsHeader
        case let .chat(_, peer, _, _, _):
            return .chat(peer.id)
        }
    }

    private var sortIndex: Int32 {
        switch self {
        case .usageHeader:
            return 0
        case .messages:
            return 1
        case .files:
            return 2
        case .deleteAll:
            return 3
        case .deleteInfo:
            return 4
        case .chatsHeader:
            return 5
        case let .chat(index, _, _, _, _):
            return 6 + index
        }
    }

    static func ==(lhs: DGSavedDeletedEntry, rhs: DGSavedDeletedEntry) -> Bool {
        switch lhs {
        case let .usageHeader(lhsText):
            if case let .usageHeader(rhsText) = rhs, lhsText == rhsText {
                return true
            }
            return false
        case let .messages(lhsTitle, lhsValue):
            if case let .messages(rhsTitle, rhsValue) = rhs, lhsTitle == rhsTitle, lhsValue == rhsValue {
                return true
            }
            return false
        case let .files(lhsTitle, lhsValue):
            if case let .files(rhsTitle, rhsValue) = rhs, lhsTitle == rhsTitle, lhsValue == rhsValue {
                return true
            }
            return false
        case let .deleteAll(lhsTitle, lhsEnabled):
            if case let .deleteAll(rhsTitle, rhsEnabled) = rhs, lhsTitle == rhsTitle, lhsEnabled == rhsEnabled {
                return true
            }
            return false
        case let .deleteInfo(lhsText):
            if case let .deleteInfo(rhsText) = rhs, lhsText == rhsText {
                return true
            }
            return false
        case let .chatsHeader(lhsText):
            if case let .chatsHeader(rhsText) = rhs, lhsText == rhsText {
                return true
            }
            return false
        case let .chat(lhsIndex, lhsPeer, lhsText, lhsEditing, lhsEnabled):
            if case let .chat(rhsIndex, rhsPeer, rhsText, rhsEditing, rhsEnabled) = rhs, lhsIndex == rhsIndex, lhsPeer == rhsPeer, lhsText == rhsText, lhsEditing == rhsEditing, lhsEnabled == rhsEnabled {
                return true
            }
            return false
        }
    }

    static func <(lhs: DGSavedDeletedEntry, rhs: DGSavedDeletedEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DGSavedDeletedArguments
        let languageCode = presentationData.strings.primaryComponent.languageCode
        let iconColor = presentationData.theme.list.itemPrimaryTextColor
        switch self {
        case let .usageHeader(text), let .chatsHeader(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .messages(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.donutgramOutlineIcon("tray.full", color: iconColor), title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .files(title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesSettings.donutgramOutlineIcon("doc", color: iconColor), title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .deleteAll(title, enabled):
            // A disabled action item still calls its action.
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .destructive : .disabled, alignment: .natural, sectionId: self.section, style: .blocks, action: {
                if enabled {
                    arguments.deleteAll()
                }
            })
        case let .deleteInfo(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .chat(_, peer, text, editing, enabled):
            let revealOptions = ItemListPeerItemRevealOptions(options: [ItemListPeerItemRevealOption(type: .destructive, title: dgLocalized("Удалить", languageCode: languageCode), action: {
                if enabled {
                    arguments.deleteChat(peer)
                }
            })])
            return ItemListPeerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, context: arguments.context, peer: peer, presence: nil, text: .text(text, .secondary), label: .none, editing: editing, revealOptions: revealOptions, switchValue: nil, enabled: true, selectable: true, sectionId: self.section, action: {
                arguments.openChat(peer)
            }, setPeerIdWithRevealedOptions: { previousId, id in
                arguments.setPeerIdWithRevealedOptions(previousId, id)
            }, removePeer: { _ in
                if enabled {
                    arguments.deleteChat(peer)
                }
            })
        }
    }
}

private struct DGSavedDeletedState: Equatable {
    var editing = false
    var searching = false
    var deleting = false
    var peerIdWithRevealedOptions: EnginePeer.Id?
}

/// «Сохранённые удалённые» in «Удалённые и правки»: how many saved deleted messages the account keeps, how much
/// their files take, deleting them, all at once or one chat at a time, and searching them by text.
public func dgSavedDeletedMessagesController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let statePromise = ValuePromise(DGSavedDeletedState(), ignoreRepeated: true)
    let stateValue = Atomic(value: DGSavedDeletedState())
    let updateState: ((DGSavedDeletedState) -> DGSavedDeletedState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    // Counted again after every deletion and on return from a chat; the previous numbers stay
    // until the new ones are ready.
    let usagePromise = Promise<DonutgramPreservedMessagesUsage?>(nil)
    let reloadUsage: () -> Void = {
        usagePromise.set(context.engine.messages.donutgramPreservedMessagesUsage()
        |> map(Optional.init))
    }
    var presentControllerImpl: ((ViewController) -> Void)?
    var navigationControllerImpl: (() -> NavigationController?)?
    var dismissInputImpl: (() -> Void)?

    let performDelete: (EnginePeer.Id?) -> Void = { peerId in
        updateState { state in
            var state = state
            state.deleting = true
            state.editing = false
            state.peerIdWithRevealedOptions = nil
            return state
        }
        // Not cancelled when the page closes: the deletion finishes in the background.
        let _ = (context.engine.messages.donutgramDeletePreservedMessages(peerId: peerId)
        |> deliverOnMainQueue).start(completed: {
            updateState { state in
                var state = state
                state.deleting = false
                return state
            }
            reloadUsage()
        })
    }
    let confirmDelete: (String, String, EnginePeer.Id?) -> Void = { title, text, peerId in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        presentControllerImpl?(textAlertController(context: context, title: title, text: text, actions: [
            TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: presentationData.strings.Common_Delete, action: {
                performDelete(peerId)
            })
        ]))
    }

    let arguments = DGSavedDeletedArguments(context: context, deleteAll: {
        let languageCode = context.sharedContext.currentPresentationData.with { $0 }.strings.primaryComponent.languageCode
        confirmDelete(dgLocalized("Удалить все сохранённые удалённые?", languageCode: languageCode), dgLocalized("Сообщения, их история правок и скачанные файлы будут удалены с этого устройства. Вернуть их будет нельзя.", languageCode: languageCode), nil)
    }, deleteChat: { peer in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let languageCode = presentationData.strings.primaryComponent.languageCode
        let name = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
        confirmDelete(dgLocalized("Удалить сохранённые удалённые?", languageCode: languageCode), dgLocalized("Сохранённые удалённые из «%@», их история правок и скачанные файлы будут удалены с этого устройства. Вернуть их будет нельзя.", languageCode: languageCode).replacingOccurrences(of: "%@", with: name), peer.id)
    }, openChat: { peer in
        guard let navigationController = navigationControllerImpl?() else {
            return
        }
        context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), keepStack: .always))
    }, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
        updateState { state in
            var state = state
            if (peerId == nil && fromPeerId == state.peerIdWithRevealedOptions) || (peerId != nil && fromPeerId == nil) {
                state.peerIdWithRevealedOptions = peerId
            }
            return state
        }
    })

    // Opens a found message in its chat; the search stays open for the way back.
    let openFoundMessage: (EnginePeer, EngineMessage) -> Void = { peer, message in
        guard let navigationController = navigationControllerImpl?() else {
            return
        }
        dismissInputImpl?()
        if case let .channel(channel) = peer, channel.flags.contains(.isForum), let threadId = message.threadId {
            let _ = context.sharedContext.navigateToForumThread(context: context, peerId: peer.id, threadId: threadId, messageId: message.id, navigationController: navigationController, activateInput: nil, scrollToEndIfExists: false, keepStack: .always, animated: true).startStandalone()
        } else {
            context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: context, chatLocation: .peer(peer), subject: .message(id: .id(message.id), highlight: ChatControllerSubject.MessageHighlight(quote: nil), timecode: nil, setupReply: false), keepStack: .always))
        }
    }

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get(), usagePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state, usage -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let languageCode = presentationData.strings.primaryComponent.languageCode
        let sizeFormatting = DataSizeStringFormatting(decimalSeparator: presentationData.dateTimeFormat.decimalSeparator, byte: presentationData.strings.FileSize_B(_:), kilobyte: presentationData.strings.FileSize_KB(_:), megabyte: presentationData.strings.FileSize_MB(_:), gigabyte: presentationData.strings.FileSize_GB(_:))
        // A chat this account no longer knows has no row; «Удалить все» still deletes its messages.
        let chats = (usage?.chats ?? []).filter { $0.peer != nil }

        var rightNavigationButton: ItemListNavigationButton?
        var secondaryRightNavigationButton: ItemListNavigationButton?
        if !chats.isEmpty && !state.deleting {
            if state.editing {
                rightNavigationButton = ItemListNavigationButton(content: .icon(.done), style: .bold, enabled: true, action: {
                    updateState { state in
                        var state = state
                        state.editing = false
                        return state
                    }
                })
            } else {
                rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Edit), style: .regular, enabled: true, action: {
                    updateState { state in
                        var state = state
                        state.editing = true
                        return state
                    }
                })
                secondaryRightNavigationButton = ItemListNavigationButton(content: .icon(.search), style: .regular, enabled: true, action: {
                    updateState { state in
                        var state = state
                        state.searching = true
                        state.peerIdWithRevealedOptions = nil
                        return state
                    }
                })
            }
        }

        var searchItem: ItemListControllerSearch?
        if state.searching {
            searchItem = DGSavedDeletedSearchItem(context: context, cancel: {
                updateState { state in
                    var state = state
                    state.searching = false
                    return state
                }
            }, openMessage: openFoundMessage, dismissInput: {
                dismissInputImpl?()
            })
        }

        var entries: [DGSavedDeletedEntry] = []
        entries.append(.usageHeader(dgLocalized("ХРАНИЛИЩЕ", languageCode: languageCode)))
        entries.append(.messages(dgLocalized("Сообщения", languageCode: languageCode), usage.map { "\($0.messageCount)" } ?? "…"))
        entries.append(.files(dgLocalized("Файлы", languageCode: languageCode), usage.map { dataSizeString($0.fileSize, formatting: sizeFormatting) } ?? "…"))
        entries.append(.deleteAll(dgLocalized(state.deleting ? "Удаление…" : "Удалить все", languageCode: languageCode), !state.deleting && (usage?.messageCount ?? 0) > 0))
        entries.append(.deleteInfo(dgLocalized("Сохранённые удалённые хранятся только на этом устройстве. Если выключить «Сохранять удалённые сообщения», уже сохранённые останутся.", languageCode: languageCode)))
        if !chats.isEmpty {
            entries.append(.chatsHeader(dgLocalized("ЧАТЫ", languageCode: languageCode)))
            for (index, chat) in chats.enumerated() {
                guard let peer = chat.peer else {
                    continue
                }
                var text = presentationData.strings.Conversation_Messages(Int32(clamping: chat.messageCount))
                if chat.fileSize > 0 {
                    text += " · " + dataSizeString(chat.fileSize, formatting: sizeFormatting)
                }
                let editing = ItemListPeerItemEditing(editable: !state.deleting, editing: state.editing && !state.deleting, revealed: chat.peerId == state.peerIdWithRevealedOptions)
                entries.append(.chat(Int32(index), peer, text, editing, !state.deleting))
            }
        }

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(dgLocalized("Сохранённые удалённые", languageCode: languageCode)), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, secondaryRightNavigationButton: secondaryRightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, searchItem: searchItem, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    presentControllerImpl = { [weak controller] alert in
        controller?.present(alert, in: .window(.root))
    }
    navigationControllerImpl = { [weak controller] in
        return controller?.navigationController as? NavigationController
    }
    dismissInputImpl = { [weak controller] in
        controller?.view.endEditing(true)
    }
    // A message deleted in a chat opened from here changes the numbers.
    controller.didAppear = { firstTime in
        if !firstTime {
            reloadUsage()
        }
    }
    reloadUsage()
    return controller
}
