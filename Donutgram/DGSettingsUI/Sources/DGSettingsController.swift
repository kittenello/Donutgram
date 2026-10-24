import Foundation
import Darwin
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import SettingsUI
import UndoUI
import ContextUI
import AppBundle
import DGSimpleSettings

struct DGListState: Equatable { var revision: Int = 0 }

/// One choice in the menu of a `.menu` row. Picking it passes the key to the page's `select`, as a checkbox does.
struct DGMenuOption {
    let key: String
    let title: String
    let isSelected: Bool
}

final class DGListArguments {
    let context: AccountContext
    let toggle: (String, Bool) -> Void
    let select: (String) -> Void
    let open: (String) -> Void
    let openMenu: (String) -> Void
    let textUpdated: (String, String) -> Void
    init(context: AccountContext, toggle: @escaping (String, Bool) -> Void, select: @escaping (String) -> Void, open: @escaping (String) -> Void, openMenu: @escaping (String) -> Void, textUpdated: @escaping (String, String) -> Void) {
        self.context = context
        self.toggle = toggle
        self.select = select
        self.open = open
        self.openMenu = openMenu
        self.textUpdated = textUpdated
    }
}

enum DGListEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case toggle(Int32, Int32, String, String, Bool, Bool)
    case disclosure(Int32, Int32, String, String, String)
    // A section of the root: key, title and state, then the SF Symbol drawn in white on the icon's RGB color.
    // Only the root has icons: rows inside the sections have none, as in Telegram's own settings.
    case rootRow(Int32, Int32, String, String, String, String, UInt32)
    // A choice made in place: the row shows the current value and opens the page's `menu` for its key.
    case menu(Int32, Int32, String, String, String)
    // A one-off action, such as reading all messages: the page's `perform` runs it.
    case action(Int32, Int32, String, String)
    // A value to read, such as the app version.
    case value(Int32, Int32, String, String, String)
    case checkbox(Int32, Int32, String, String, Bool)
    case info(Int32, Int32, String)
    case input(Int32, Int32, String, String, String)
    // The flags are diff keys: the bubbles read DGSimpleSettings at layout time.
    case messagePreview(Int32, Int32, DGMessagePreviewConfiguration, TelegramMediaFile?)
    case chatListPreview(Int32, Int32, Bool, Bool, Bool, Bool, Int)
    case tabBarPreview(Int32, Int32, DGTabBarLayout)
    // The Int is the current icon's DGSimpleSettings.appMarks index: a diff key, so the grid moves its selection.
    case appIcons(Int32, Int32, Int)
    case islandStyles(Int32, Int32, Int)
    case speedSlider(Int32, Int32, Int)
    case stickerSizeSlider(Int32, Int32, Int)
    // Size, time, checks, the raw reply options and the shape, then the message settings the preview's
    // bubbles show (tails, seconds, reply colors, premium emoji): diff keys, like messagePreview.
    case stickerPreview(Int32, Int32, Int, Bool, Bool, Int, Int, DGMessagePreviewConfiguration, TelegramMediaFile?, TelegramMediaFile?)
    case stickerShape(Int32, Int32, Int)
    // The «Иконка и остров» row: DGSimpleSettings.appMarks indices of the icon and of the island, as diff keys.
    case iconAndIsland(Int32, Int32, Int, Int)
    // «Предпросмотр» on «Иконка и остров»: DGSimpleSettings.appMarks indices of the icon and of the island.
    case iconIslandPreview(Int32, Int32, Int, Int)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .toggle(_, section, _, _, _, _), let .disclosure(_, section, _, _, _), let .rootRow(_, section, _, _, _, _, _), let .menu(_, section, _, _, _), let .action(_, section, _, _), let .value(_, section, _, _, _), let .checkbox(_, section, _, _, _), let .info(_, section, _), let .input(_, section, _, _, _), let .messagePreview(_, section, _, _), let .chatListPreview(_, section, _, _, _, _, _), let .tabBarPreview(_, section, _),let .appIcons(_, section, _), let .islandStyles(_, section, _), let .speedSlider(_, section, _), let .iconAndIsland(_, section, _, _), let .iconIslandPreview(_, section, _, _), let .stickerSizeSlider(_, section, _), let .stickerPreview(_, section, _, _, _, _, _, _, _, _), let .stickerShape(_, section, _): return section
        }
    }
    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .toggle(id, _, _, _, _, _), let .disclosure(id, _, _, _, _), let .rootRow(id, _, _, _, _, _, _), let .menu(id, _, _, _, _), let .action(id, _, _, _), let .value(id, _, _, _, _), let .checkbox(id, _, _, _, _), let .info(id, _, _), let .input(id, _, _, _, _), let .messagePreview(id, _, _, _), let .chatListPreview(id, _, _, _, _, _, _), let .tabBarPreview(id, _, _),let .appIcons(id, _, _), let .islandStyles(id, _, _), let .speedSlider(id, _, _), let .iconAndIsland(id, _, _, _), let .iconIslandPreview(id, _, _, _), let .stickerSizeSlider(id, _, _), let .stickerPreview(id, _, _, _, _, _, _, _, _, _), let .stickerShape(id, _, _): return id
        }
    }
    // The tag the row's node reports: the one item(presentationData:arguments:) gives the item,
    // or the fixed key of the speed slider and chat list preview nodes.
    var tag: ItemListItemTag? {
        switch self {
        case let .toggle(_, _, key, _, _, _), let .disclosure(_, _, key, _, _), let .rootRow(_, _, key, _, _, _, _), let .menu(_, _, key, _, _), let .action(_, _, key, _), let .value(_, _, key, _, _), let .checkbox(_, _, key, _, _), let .input(_, _, key, _, _): return DGSettingItemTag(key: key)
        case .iconAndIsland: return DGSettingItemTag(key: "iconAndIsland")
        case .speedSlider: return DGSettingItemTag(key: "downloadAcceleration")
        case .tabBarPreview: return DGSettingItemTag(key: "tabBarPreview")
        case .chatListPreview: return DGSettingItemTag(key: "chatListPreview")
        case .stickerSizeSlider: return DGSettingItemTag(key: "stickerSize")
        case .stickerShape: return DGSettingItemTag(key: "stickerShape")
        default: return nil
        }
    }
    static func < (lhs: DGListEntry, rhs: DGListEntry) -> Bool { lhs.stableId < rhs.stableId }

    func localized(languageCode: String) -> DGListEntry {
        func tr(_ text: String) -> String { dgLocalized(text, languageCode: languageCode) }
        switch self {
        case let .header(id, section, title): return .header(id, section, tr(title))
        case let .toggle(id, section, key, title, value, enabled): return .toggle(id, section, key, tr(title), value, enabled)
        case let .disclosure(id, section, key, title, label): return .disclosure(id, section, key, tr(title), tr(label))
        case let .rootRow(id, section, key, title, label, symbol, color): return .rootRow(id, section, key, tr(title), tr(label), symbol, color)
        case let .menu(id, section, key, title, label): return .menu(id, section, key, tr(title), tr(label))
        case let .action(id, section, key, title): return .action(id, section, key, tr(title))
        case let .value(id, section, key, title, value): return .value(id, section, key, tr(title), value)
        case let .checkbox(id, section, key, title, checked): return .checkbox(id, section, key, tr(title), checked)
        case let .info(id, section, text): return .info(id, section, tr(text))
        case let .input(id, section, key, value, placeholder): return .input(id, section, key, value, tr(placeholder))
        default: return self
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DGListArguments
        let languageCode = presentationData.strings.primaryComponent.languageCode
        switch self {
        case let .header(_, _, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .toggle(_, _, key, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, enableInteractiveChanges: enabled, enabled: enabled, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { arguments.toggle(key, $0) }, tag: DGSettingItemTag(key: key))
        case let .disclosure(_, _, key, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: { arguments.open(key) }, tag: DGSettingItemTag(key: key))
        case let .rootRow(_, _, key, title, label, symbol, color):
            let icon = PresentationResourcesSettings.donutgramOutlineIcon(symbol, color: .white, backgroundColor: UIColor(rgb: color))
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: { arguments.open(key) }, tag: DGSettingItemTag(key: key))
        case let .menu(_, _, key, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .optionArrows, action: { arguments.openMenu(key) }, tag: DGSettingItemTag(key: key))
        case let .action(_, _, key, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { arguments.open(key) }, tag: DGSettingItemTag(key: key))
        case let .value(_, _, key, title, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: value, sectionId: self.section, style: .blocks, disclosureStyle: .none, action: nil, tag: DGSettingItemTag(key: key))
        case let .checkbox(_, _, key, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: { arguments.select(key) }, tag: DGSettingItemTag(key: key))
        case let .info(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .markdown(text), sectionId: self.section)
        case let .input(_, _, key, value, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: value, placeholder: placeholder, type: key == "level" ? .number : .regular(capitalization: false, autocorrection: false), clearType: .always, tag: DGSettingItemTag(key: key), sectionId: self.section, textUpdated: { arguments.textUpdated(key, $0) }, action: {})
        case let .messagePreview(_, _, _, emoji):
            return donutgramMessagePreviewItem(context: arguments.context, sectionId: self.section, emoji: emoji)
        case let .chatListPreview(_, _, snow, hideEmojiStatus, centerTitle, hideSearch, titleMode):
            return DGChatListPreviewItem(context: arguments.context, theme: presentationData.theme, sectionId: self.section, snow: snow, hideEmojiStatus: hideEmojiStatus, centerTitle: centerTitle, hideSearch: hideSearch, titleMode: titleMode)
        case let .tabBarPreview(_, _, layout):
            return DGTabBarPreviewItem(context: arguments.context, theme: presentationData.theme, strings: presentationData.strings, sectionId: self.section, layout: layout)
        case .appIcons:
            return donutgramAppIconItem(context: arguments.context, sectionId: self.section, updated: { arguments.select("refreshAppIcon") })
        case let .islandStyles(_, _, value):
            return DGIslandStyleItem(theme: presentationData.theme, languageCode: languageCode, sectionId: self.section, value: value, updated: { arguments.select("islandStyle:\($0)") })
        case let .speedSlider(_, _, value):
            return DGSpeedSliderItem(theme: presentationData.theme, languageCode: languageCode, sectionId: self.section, value: value, updated: { arguments.select("downloadAcceleration:\($0)") })
        case let .stickerSizeSlider(_, _, size):
            return DGStickerAppearanceItem(theme: presentationData.theme, languageCode: languageCode, sectionId: self.section, shapePicker: false, size: size, shape: 0, updated: { arguments.select($0) })
        case let .stickerPreview(_, _, _, _, _, _, _, _, sticker, emoji):
            return donutgramStickerPreviewItem(context: arguments.context, sectionId: self.section, sticker: sticker, emoji: emoji)
        case let .stickerShape(_, _, shape):
            return DGStickerAppearanceItem(theme: presentationData.theme, languageCode: languageCode, sectionId: self.section, shapePicker: true, size: DGSimpleSettings.shared.stickerSize, shape: shape, updated: { arguments.select($0) })
        case let .iconAndIsland(_, _, iconMark, islandMark):
            return donutgramIconAndIslandItem(presentationData: presentationData, sectionId: self.section, iconName: DGSimpleSettings.appMarks[iconMark].iconName, islandMark: islandMark, action: { arguments.open("iconAndIsland") }, tag: DGSettingItemTag(key: "iconAndIsland"))
        case let .iconIslandPreview(_, _, iconMark, islandMark):
            return DGIconIslandPreviewItem(theme: presentationData.theme, languageCode: languageCode, sectionId: self.section, icon: DGSimpleSettings.appMarks[iconMark], island: DGSimpleSettings.appMarks[islandMark])
        }
    }
}

func dgController(context: AccountContext, page: DGSettingsPage, title: String, focusKey: String?, entries: @escaping () -> [DGListEntry], restartRequiredKeys: Set<String> = [], additionalUpdates: Signal<Void, NoError> = .single(()), toggle: @escaping (String, Bool) -> Void = { _, _ in }, select: @escaping (String) -> Void = { _ in }, menu: @escaping (String) -> [DGMenuOption] = { _ in [] }, textUpdated: @escaping (String, String) -> Void = { _, _ in }, open: @escaping (String) -> ViewController? = { _ in nil }, perform: @escaping (String, ViewController) -> Void = { _, _ in }) -> ViewController {
    let focusTag = focusKey.map { DGSettingItemTag(key: $0) }
    let initialState = DGListState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let refresh = {
        statePromise.set(stateValue.modify { state in
            var state = state
            state.revision += 1
            return state
        })
    }
    var pushControllerImpl: ((ViewController) -> Void)?
    var performImpl: ((String) -> Void)?
    var presentMenuImpl: ((String) -> Void)?
    var presentRestartNoticeImpl: (() -> Void)?
    // Set when a sub-page is pushed: it can change a value this page shows (e.g. the transcription service label).
    var needsRefreshOnAppear = false
    let arguments = DGListArguments(context: context, toggle: { key, value in
        toggle(key, value)
        refresh()
        if restartRequiredKeys.contains(key) { presentRestartNoticeImpl?() }
    }, select: { key in select(key); refresh() }, open: { key in
        if let controller = open(key) {
            needsRefreshOnAppear = true
            pushControllerImpl?(controller)
        } else {
            performImpl?(key)
        }
    }, openMenu: { key in presentMenuImpl?(key) }, textUpdated: { key, value in textUpdated(key, value) })
    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get(), additionalUpdates)
    |> map { presentationData, _, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let languageCode = presentationData.strings.primaryComponent.languageCode
        let controllerState = ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(dgLocalized(title, languageCode: languageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listEntries = entries().map { $0.localized(languageCode: languageCode) }
        // Scroll to a linked row by index: on open the list builds nodes only for the visible area plus 500 pt, and a lookup
        // by tag (ensureVisibleItemTag, itemNode(forTag:)) can't reach rows below that. The list applies this to the first state only.
        // .Down: with .Up, ListView snaps the gap a centered bottom row leaves under the list to the top, scrolling the row away.
        var focusScroll: ListViewScrollToItem?
        if let focusTag, let index = listEntries.firstIndex(where: { $0.tag?.isEqual(to: focusTag) ?? false }) {
            focusScroll = ListViewScrollToItem(index: index, position: .center(.top), animated: false, curve: .Default(duration: nil), directionHint: .Down)
        }
        let listState = ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: listEntries, style: .blocks, initialScrollToItem: focusScroll, animateChanges: true)
        return (controllerState, (listState, arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    let longPressHandler = DGSettingsLongPressHandler(context: context, controller: controller, page: page)
    // As in upstream theme settings: the chat preview item lays out views, so list updates must run on the main thread.
    controller.alwaysSynchronous = true
    // Re-read the entries on return from a sub-page, but not on other re-appearances (tab switches, dismissed modals):
    // that would overwrite a text field the user is still editing with its stored value.
    controller.didAppear = { [weak controller] firstTime in
        if firstTime {
            let gesture = UILongPressGestureRecognizer(target: longPressHandler, action: #selector(DGSettingsLongPressHandler.handle(_:)))
            // Keep the default cancelsTouchesInView: when the menu opens, the list gets touchesCancelled
            // and does not open the row on release, as with its own scroll pan.
            gesture.delegate = longPressHandler
            controller?.view.addGestureRecognizer(gesture)
        }
        if !firstTime && needsRefreshOnAppear {
            needsRefreshOnAppear = false
            refresh()
        }
    }
    if let focusTag {
        // One shot: the first transaction has already scrolled to the row. A retry on later transactions would flash
        // a row that shows up only afterwards (e.g. when its parent toggle is switched on), long after the link was opened.
        var focusHandled = false
        controller.afterTransactionCompleted = { [weak controller] in
            guard !focusHandled, let controller else { return }
            focusHandled = true
            if let node = controller.itemNode(forTag: focusTag) {
                controller.ensureItemNodeVisible(node, animated: false)
                (node as? ItemListItemNode)?.displayHighlight()
            }
        }
    }
    pushControllerImpl = { [weak controller] pushed in (controller?.navigationController as? NavigationController)?.pushViewController(pushed) }
    performImpl = { [weak controller] key in
        if let controller { perform(key, controller) }
    }
    // The options open from the row's value, as in Telegram's storage settings. Picking one goes through `select`,
    // so the row shows the new value at once.
    presentMenuImpl = { [weak controller] key in
        let options = menu(key)
        guard let controller, !options.isEmpty else {
            return
        }
        var sourceNode: ItemListDisclosureItemNode?
        controller.forEachItemNode { node in
            if sourceNode == nil, let node = node as? ItemListDisclosureItemNode, (node.tag as? DGSettingItemTag)?.key == key {
                sourceNode = node
            }
        }
        guard let sourceNode else {
            return
        }
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let languageCode = presentationData.strings.primaryComponent.languageCode
        let items: [ContextMenuItem] = options.map { option -> ContextMenuItem in
            return .action(ContextMenuActionItem(text: dgLocalized(option.title, languageCode: languageCode), icon: { theme in
                if option.isSelected {
                    return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/Check"), color: theme.contextMenu.primaryColor)
                } else {
                    return UIImage()
                }
            }, action: { _, f in
                f(.default)
                select(option.key)
                refresh()
            }))
        }
        let contextController = makeContextController(presentationData: presentationData, source: .reference(DGMenuReferenceContentSource(sourceView: sourceNode.labelNode.view)), items: .single(ContextController.Items(content: .list(items))), gesture: nil)
        sourceNode.updateHasContextMenu(hasContextMenu: true)
        contextController.dismissed = { [weak sourceNode] in
            sourceNode?.updateHasContextMenu(hasContextMenu: false)
        }
        controller.presentInGlobalOverlay(contextController, with: nil)
    }
    presentRestartNoticeImpl = { [weak controller] in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(UndoOverlayController(
            presentationData: presentationData,
            content: .info(title: nil, text: dgLocalized("Необходим перезапуск", languageCode: presentationData.strings.primaryComponent.languageCode), timeout: 5.0, customUndoText: dgLocalized("Перезапустить сейчас", languageCode: presentationData.strings.primaryComponent.languageCode)),
            elevatedLayout: false,
            position: .bottom,
            action: { action in
                if case .undo = action {
                    Darwin.exit(0)
                }
                return false
            }
        ), in: .current)
    }
    return controller
}

private final class DGMenuReferenceContentSource: ContextReferenceContentSource {
    private let sourceView: UIView

    init(sourceView: UIView) {
        self.sourceView = sourceView
    }

    func transitionInfo() -> ContextControllerReferenceViewInfo? {
        return ContextControllerReferenceViewInfo(referenceView: self.sourceView, contentAreaInScreenSpace: UIScreen.main.bounds, insets: UIEdgeInsets(top: -4.0, left: 0.0, bottom: -4.0, right: 0.0))
    }
}

/// The app version, as on the App Store: «13.0».
func dgAppVersion() -> String {
    return (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? ""
}

/// The root: fifteen sections in four groups, each named after the place in the app where its settings show.
/// A section's row tells its state where there is one to tell, so the root reads what is on without opening anything.
public func dgSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    let accountId = context.account.peerId.toInt64()
    return dgController(context: context, page: .root, title: "Настройки Donutgram", focusKey: focusKey, entries: {
        let notSentByGhost = [s.ghostReadMessages, s.ghostReadStories, s.ghostSendOnline, s.ghostSendTyping].filter { !$0 }.count
        let bypassed = [s.bypassForwardRestrictions, s.allowProtectedScreenshots, s.gifUnlock].filter { $0 }.count
        let shadowBanned = s.shadowBannedPeerIds.count
        let acceleration = ["Выкл", "Быстро", "Ультра"][s.downloadAcceleration]
        var localProfile = s.visualPhoneEnabled || s.localPremium(accountId: accountId)
        localProfile = localProfile || s.visualRatingLevel(accountId: accountId) != nil || !s.visualUsernames(accountId: accountId).isEmpty
        localProfile = localProfile || !s.visualProfileId(accountId: accountId).isEmpty || s.visualLabel(accountId: accountId) != DGVisualLabel.none

        var entries: [DGListEntry] = []
        entries.append(.header(0, 0, "ПРИВАТНОСТЬ"))
        entries.append(.rootRow(1, 0, "ghost", "Режим призрака", s.ghostModeEnabled ? "Вкл · \(notSentByGhost)/4" : "Выкл", "eye.slash.fill", 0x5E5CE6))
        entries.append(.rootRow(2, 0, "saving", "Сохранение", s.saveDeletedMessages ? "Вкл" : "Выкл", "tray.and.arrow.down.fill", 0xFF9F0A))
        entries.append(.rootRow(3, 0, "bypass", "Обход ограничений", "\(bypassed)/3", "lock.open.fill", 0x30B0C7))
        entries.append(.rootRow(4, 0, "shadowBan", "Теневой бан", shadowBanned == 0 ? "Выкл" : "\(shadowBanned)", "person.crop.circle.badge.xmark", 0xFF453A))
        entries.append(.header(10, 1, "ИНТЕРФЕЙС"))
        entries.append(.rootRow(11, 1, "mainScreen", "Главный экран", "", "list.bullet", 0x0A84FF))
        entries.append(.rootRow(12, 1, "messages", "Сообщения", "", "bubble.left.and.bubble.right.fill", 0x30D158))
        entries.append(.rootRow(13, 1, "stickers", "Стикеры и реакции", "", "face.smiling.fill", 0xFF375F))
        entries.append(.rootRow(14, 1, "profiles", "Профили", "", "person.crop.circle.fill", 0xBF5AF2))
        entries.append(.rootRow(15, 1, "iconAndEffects", "Иконка и эффекты", "", "sparkles", 0xF5A623))
        entries.append(.header(20, 2, "МЕДИА И СЕТЬ"))
        entries.append(.rootRow(21, 2, "media", "Запись и воспроизведение", "", "mic.fill", 0xFF6A3D))
        entries.append(.rootRow(22, 2, "downloads", "Загрузки и сеть", acceleration, "arrow.down.circle.fill", 0x00A99D))
        entries.append(.header(30, 3, "ПРОЧЕЕ"))
        entries.append(.rootRow(31, 3, "security", "Безопасность", "", "checkmark.shield.fill", 0x8E8E93))
        entries.append(.rootRow(32, 3, "adsAndGifts", "Реклама и подарки", "", "gift.fill", 0xFF9F0A))
        entries.append(.rootRow(33, 3, "localProfile", "Локальный профиль", localProfile ? "Вкл" : "Выкл", "theatermasks.fill", 0x32ADE6))
        entries.append(.rootRow(34, 3, "about", "О Donutgram", dgAppVersion(), "info.circle.fill", 0xF2478B))
        return entries
    }, open: { key in
        return dgSectionController(context: context, key: key)
    })
}

/// The page a root row opens, by the row's key.
private func dgSectionController(context: AccountContext, key: String) -> ViewController? {
    switch key {
    case "ghost": return dgGhostSettingsController(context: context)
    case "saving": return dgSavingSettingsController(context: context)
    case "bypass": return dgBypassSettingsController(context: context)
    case "shadowBan": return dgShadowBanController(context: context)
    case "mainScreen": return dgMainScreenSettingsController(context: context)
    case "messages": return dgMessagesSettingsController(context: context)
    case "stickers": return dgStickersSettingsController(context: context)
    case "profiles": return dgProfilesSettingsController(context: context)
    case "iconAndEffects": return dgIconAndEffectsSettingsController(context: context)
    case "media": return dgMediaSettingsController(context: context)
    case "downloads": return dgDownloadsSettingsController(context: context)
    case "security": return dgSecuritySettingsController(context: context)
    case "adsAndGifts": return dgAdsAndGiftsSettingsController(context: context)
    case "localProfile": return dgLocalProfileSettingsController(context: context)
    case "about": return dgAboutController(context: context)
    default: return nil
    }
}
