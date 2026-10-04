import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import ItemListUI
import ItemListPeerItem
import ItemListPeerActionItem
import LocalizedPeerData
import UndoUI
import DGSimpleSettings

/// Bans or unbans `peer` and shows «<name> в теневом бане» or «<name> убран из теневого бана» with «Отменить».
public func dgToggleShadowBan(context: AccountContext, peer: EnginePeer, present: @escaping (ViewController) -> Void) {
    let settings = DGSimpleSettings.shared
    let peerId = peer.id.toInt64()
    let ban = !settings.isShadowBanned(peerId)
    settings.setShadowBanned(ban, peerId: peerId)
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let name = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
    let text = ban ? "\(name) в теневом бане" : "\(name) убран из теневого бана"
    present(UndoOverlayController(presentationData: presentationData, content: .info(title: nil, text: text, timeout: nil, customUndoText: "Отменить"), elevatedLayout: false, action: { action in
        if case .undo = action {
            settings.setShadowBanned(!ban, peerId: peerId)
        }
        return false
    }))
}

private final class DGShadowBanArguments {
    let context: AccountContext
    let setPeerIdWithRevealedOptions: (EnginePeer.Id?, EnginePeer.Id?) -> Void
    let addPeer: () -> Void
    let removePeer: (EnginePeer.Id) -> Void
    let openPeer: (EnginePeer) -> Void

    init(context: AccountContext, setPeerIdWithRevealedOptions: @escaping (EnginePeer.Id?, EnginePeer.Id?) -> Void, addPeer: @escaping () -> Void, removePeer: @escaping (EnginePeer.Id) -> Void, openPeer: @escaping (EnginePeer) -> Void) {
        self.context = context
        self.setPeerIdWithRevealedOptions = setPeerIdWithRevealedOptions
        self.addPeer = addPeer
        self.removePeer = removePeer
        self.openPeer = openPeer
    }
}

private enum DGShadowBanSection: Int32 {
    case peers
}

private enum DGShadowBanEntryId: Hashable {
    case add
    case peer(EnginePeer.Id)
    case info
}

private enum DGShadowBanEntry: ItemListNodeEntry {
    case add(PresentationTheme)
    // The peer, its subtitle and whether it is known to this account (an unknown one can't be opened).
    case peer(Int32, EnginePeer, String, Bool, ItemListPeerItemEditing)
    case info(String)

    var section: ItemListSectionId {
        return DGShadowBanSection.peers.rawValue
    }

    var stableId: DGShadowBanEntryId {
        switch self {
        case .add:
            return .add
        case let .peer(_, peer, _, _, _):
            return .peer(peer.id)
        case .info:
            return .info
        }
    }

    private var sortIndex: Int32 {
        switch self {
        case .add:
            return 0
        case let .peer(index, _, _, _, _):
            return 1 + index
        case .info:
            return Int32.max
        }
    }

    static func ==(lhs: DGShadowBanEntry, rhs: DGShadowBanEntry) -> Bool {
        switch lhs {
        case let .add(lhsTheme):
            if case let .add(rhsTheme) = rhs, lhsTheme === rhsTheme {
                return true
            }
            return false
        case let .peer(lhsIndex, lhsPeer, lhsText, lhsKnown, lhsEditing):
            if case let .peer(rhsIndex, rhsPeer, rhsText, rhsKnown, rhsEditing) = rhs, lhsIndex == rhsIndex, lhsPeer == rhsPeer, lhsText == rhsText, lhsKnown == rhsKnown, lhsEditing == rhsEditing {
                return true
            }
            return false
        case let .info(lhsText):
            if case let .info(rhsText) = rhs, lhsText == rhsText {
                return true
            }
            return false
        }
    }

    static func <(lhs: DGShadowBanEntry, rhs: DGShadowBanEntry) -> Bool {
        return lhs.sortIndex < rhs.sortIndex
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DGShadowBanArguments
        switch self {
        case let .add(theme):
            return ItemListPeerActionItem(presentationData: presentationData, systemStyle: .glass, icon: PresentationResourcesItemList.addPersonIcon(theme), title: "Добавить", sectionId: self.section, height: .generic, editing: false, action: {
                arguments.addPeer()
            })
        case let .peer(_, peer, text, isKnown, editing):
            let revealOptions = ItemListPeerItemRevealOptions(options: [ItemListPeerItemRevealOption(type: .destructive, title: "Убрать", action: {
                arguments.removePeer(peer.id)
            })])
            return ItemListPeerItem(presentationData: presentationData, systemStyle: .glass, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, context: arguments.context, peer: peer, presence: nil, text: .text(text, .secondary), label: .none, editing: editing, revealOptions: revealOptions, switchValue: nil, enabled: true, selectable: isKnown, sectionId: self.section, action: {
                arguments.openPeer(peer)
            }, setPeerIdWithRevealedOptions: { previousId, id in
                arguments.setPeerIdWithRevealedOptions(previousId, id)
            }, removePeer: { peerId in
                arguments.removePeer(peerId)
            })
        case let .info(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private struct DGShadowBanState: Equatable {
    var editing = false
    var peerIdWithRevealedOptions: EnginePeer.Id?
}

// A row for an id this account doesn't know (e.g. banned from another account): it can still be removed.
private func dgUnknownShadowBanPeer(_ peerId: EnginePeer.Id) -> EnginePeer {
    return .user(TelegramUser(id: peerId, accessHash: nil, firstName: "Неизвестный", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil))
}

private func dgShadowBanSubtitle(_ peer: EnginePeer?, peerId: EnginePeer.Id) -> String {
    guard let peer else {
        return "ID \(peerId.id._internalGetInt64Value())"
    }
    if let username = peer.addressName {
        return "@\(username)"
    }
    switch peer {
    case let .user(user):
        return user.botInfo != nil ? "бот" : "пользователь"
    case .channel:
        return "канал"
    default:
        return ""
    }
}

/// «Теневой бан» in «Основные»: the banned people, bots and channels, adding and removing them.
public func dgShadowBanController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let statePromise = ValuePromise(DGShadowBanState(), ignoreRepeated: true)
    let stateValue = Atomic(value: DGShadowBanState())
    let updateState: ((DGShadowBanState) -> DGShadowBanState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }
    var pushControllerImpl: ((ViewController) -> Void)?

    let arguments = DGShadowBanArguments(context: context, setPeerIdWithRevealedOptions: { peerId, fromPeerId in
        updateState { state in
            var state = state
            if (peerId == nil && fromPeerId == state.peerIdWithRevealedOptions) || (peerId != nil && fromPeerId == nil) {
                state.peerIdWithRevealedOptions = peerId
            }
            return state
        }
    }, addPeer: {
        let controller = context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: context, filter: [.excludeGroups, .excludeSecretChats, .excludeSavedMessages, .removeSearchHeader, .excludeRecent, .doNotSearchMessages], title: "Теневой бан"))
        controller.peerSelected = { [weak controller] peer, _ in
            if DonutgramShadowBan.canBan(peer, accountPeerId: context.account.peerId) {
                DGSimpleSettings.shared.setShadowBanned(true, peerId: peer.id.toInt64())
            }
            controller?.dismiss()
        }
        pushControllerImpl?(controller)
    }, removePeer: { peerId in
        DGSimpleSettings.shared.setShadowBanned(false, peerId: peerId.toInt64())
    }, openPeer: { peer in
        if let controller = context.sharedContext.makePeerInfoController(context: context, updatedPresentationData: nil, peer: peer, mode: .generic, avatarInitiallyExpanded: false, fromChat: false, requestsContext: nil) {
            pushControllerImpl?(controller)
        }
    })

    let bannedPeers: Signal<([EnginePeer.Id], [EnginePeer.Id: EnginePeer]), NoError> = DonutgramShadowBan.stateSignal()
    |> map { state -> [EnginePeer.Id] in
        return state.bannedPeerIds.sorted().map { EnginePeer.Id($0) }
    }
    |> distinctUntilChanged
    |> mapToSignal { peerIds -> Signal<([EnginePeer.Id], [EnginePeer.Id: EnginePeer]), NoError> in
        return context.engine.data.subscribe(EngineDataMap(peerIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) }))
        |> map { peerMap -> ([EnginePeer.Id], [EnginePeer.Id: EnginePeer]) in
            var peers: [EnginePeer.Id: EnginePeer] = [:]
            for (peerId, peer) in peerMap {
                if let peer {
                    peers[peerId] = peer
                }
            }
            return (peerIds, peers)
        }
    }

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get(), bannedPeers)
    |> deliverOnMainQueue
    |> map { presentationData, state, bannedPeers -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (peerIds, peers) = bannedPeers
        var rightNavigationButton: ItemListNavigationButton?
        if !peerIds.isEmpty {
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
            }
        }

        // Peers known to this account first, by name; unknown ids after them.
        let orderedPeerIds = peerIds.sorted { lhs, rhs in
            switch (peers[lhs], peers[rhs]) {
            case let (lhsPeer?, rhsPeer?):
                return lhsPeer.compactDisplayTitle.localizedCaseInsensitiveCompare(rhsPeer.compactDisplayTitle) == .orderedAscending
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return lhs < rhs
            }
        }

        var entries: [DGShadowBanEntry] = [.add(presentationData.theme)]
        for (index, peerId) in orderedPeerIds.enumerated() {
            let peer = peers[peerId]
            entries.append(.peer(Int32(index), peer ?? dgUnknownShadowBanPeer(peerId), dgShadowBanSubtitle(peer, peerId: peerId), peer != nil, ItemListPeerItemEditing(editable: true, editing: state.editing, revealed: peerId == state.peerIdWithRevealedOptions)))
        }
        entries.append(.info("Сообщения этих людей скрыты в группах, комментариях и каналах только на этом устройстве. Они об этом не узнают. Личные чаты не меняются."))

        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text("Теневой бан"), leftNavigationButton: nil, rightNavigationButton: rightNavigationButton, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back), animateChanges: true)
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] pushed in
        (controller?.navigationController as? NavigationController)?.pushViewController(pushed)
    }
    return controller
}
