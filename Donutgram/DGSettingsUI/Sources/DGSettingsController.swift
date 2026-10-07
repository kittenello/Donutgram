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
import DGSimpleSettings

struct DGListState: Equatable { var revision: Int = 0 }

final class DGListArguments {
    let context: AccountContext
    let toggle: (String, Bool) -> Void
    let select: (String) -> Void
    let open: (String) -> Void
    let textUpdated: (String, String) -> Void
    init(context: AccountContext, toggle: @escaping (String, Bool) -> Void, select: @escaping (String) -> Void, open: @escaping (String) -> Void, textUpdated: @escaping (String, String) -> Void) {
        self.context = context
        self.toggle = toggle
        self.select = select
        self.open = open
        self.textUpdated = textUpdated
    }
}

private func dgSettingsSymbol(key: String, title: String) -> String {
    switch key {
    case "downloads", "downloadTikTok", "downloadShorts": return "arrow.down.to.line"
    case "spy", "ghost", "options", "offline": return "eye.slash"
    case "chats", "messages", "tails", "replies": return "bubble.left.and.bubble.right"
    case "appearance", "customBackgrounds": return "paintbrush"
    case "wideChannelPosts": return "rectangle.expand.vertical"
    case "channelBottomButton": return "rectangle.bottomthird.inset.filled"
    case "glow", "avatarGlow", "reactionGlow": return "sparkles"
    case "support": return "questionmark.circle"
    case "saveDeleted", "transparentDeleted": return "tray.full"
    case "saveEdits": return "pencil"
    case "saveOnce": return "lock"
    case "saveBots": return "bubble.left"
    case "bypassForward": return "arrowshape.turn.up.right"
    case "readOnAction": return "checkmark.message"
    case "scheduled": return "calendar"
    case "silent": return "speaker.slash"
    case "stories", "hideStories", "saveProtectedStories": return "play.rectangle"
    case "premiumStatuses": return "star.slash"
    case "hideTabBar", "wideTabBar": return "rectangle.split.3x1"
    case "integratedTabSearch": return "magnifyingglass"
    case "tabSearchOnLeft": return "arrow.left"
    case "contacts", "mutualContact": return "person.2"
    case "calls", "confirmCalls": return "phone"
    case "profileId", "visualId", "dialogIdFormat": return "number"
    case "relativeOnlineTime": return "clock.arrow.circlepath"
    case "hidePhoneNumber": return "phone.down"
    case "dc": return "network"
    case "regDate", "chatDate": return "calendar"
    case "disableAds": return "xmark.rectangle"
    case "onlyAdded", "recent": return "face.smiling"
    case "reactions", "hidePaidReactions": return "heart"
    case "hideBirthdayNotifications": return "gift"
    case "hideViaBot", "hideBotAutomation": return "cpu"
    case "showPinnedMessagesWithBot": return "pin"
    case "removeLinkPreviews": return "link"
    case "autoplayMedia", "autoplayMediaTypes": return "play.circle"
    case "seconds", "hideStickerTime", "forwardDate": return "clock"
    case "hideStickerChecks": return "checkmark"
    case "foldersAtBottom": return "folder"
    case "transcription": return "waveform"
    case "camera", "rearCamera", "rememberCamera", "zoomSlider", "staticZoom": return "camera.rotate"
    case "pauseMusicOnRecording": return "music.note"
    case "builtInMic": return "mic"
    case "autoPause", "autoPauseMedia": return "pause.circle"
    case "editedIcon": return "pencil.line"
    case "onlineIndicator": return "circle.fill"
    case "greetingSticker": return "hand.wave"
    case "mentionComma": return "at"
    case "mentionAvatars": return "person.crop.circle"
    case "gifUnlock": return "film"
    case "snow": return "snowflake"
    case "islandFollowsIcon": return "link"
    case "pollResultsBeforeVoting": return "chart.bar"
    case "channelForwardCount": return "arrowshape.turn.up.right"
    case "doubleTapSeek": return "goforward.15"
    case "hideArchive", "openArchiveOnPull": return "archivebox"
    case "downloadAcceleration": return "arrow.down.circle"
    case "accelerateUpload": return "arrow.up.circle"
    case "localPremium": return "star"
    case "visualPhone", "number": return "phone"
    case "visualRating": return "star"
    case "visualUsernames": return "at"
    case "signDownloads": return "text.alignleft"
    case "online": return "person.crop.circle"
    case "typing": return "ellipsis.bubble"
    case "shadowBan": return "person.crop.circle.badge.xmark"
    default:
        if title.contains("номер") { return "phone" }
        if title.contains("истори") { return "play.rectangle" }
        if title.contains("звука") { return "speaker.slash" }
        return "gearshape"
    }
}

enum DGListEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case toggle(Int32, Int32, String, String, Bool, Bool)
    case disclosure(Int32, Int32, String, String, String)
    case checkbox(Int32, Int32, String, String, Bool)
    case info(Int32, Int32, String)
    case input(Int32, Int32, String, String, String)
    // The flags are diff keys: the bubbles read DGSimpleSettings at layout time.
    case messagePreview(Int32, Int32, Bool, Bool, Bool, Bool)
    case chatListPreview(Int32, Int32, Bool, Bool, Bool, Bool, Int)
    case tabBarPreview(Int32, Int32, DGTabBarLayout)
    // The Int is the current icon's DGSimpleSettings.appMarks index: a diff key, so the grid moves its selection.
    case appIcons(Int32, Int32, Int)
    case islandStyles(Int32, Int32, Int)
    case speedSlider(Int32, Int32, Int)
    case stickerSizeSlider(Int32, Int32, Int)
    case stickerPreview(Int32, Int32, Int, Bool, Bool, Int, Int, TelegramMediaFile?)
    case stickerReplies(Int32, Int32, Int)
    case stickerShape(Int32, Int32, Int)
    // The «Иконка и остров» row: DGSimpleSettings.appMarks indices of the icon and of the island, as diff keys.
    case iconAndIsland(Int32, Int32, Int, Int)
    // «Предпросмотр» on «Иконка и остров»: DGSimpleSettings.appMarks indices of the icon and of the island.
    case iconIslandPreview(Int32, Int32, Int, Int)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .toggle(_, section, _, _, _, _), let .disclosure(_, section, _, _, _), let .checkbox(_, section, _, _, _), let .info(_, section, _), let .input(_, section, _, _, _), let .messagePreview(_, section, _, _, _, _), let .chatListPreview(_, section, _, _, _, _, _), let .tabBarPreview(_, section, _),let .appIcons(_, section, _), let .islandStyles(_, section, _), let .speedSlider(_, section, _), let .iconAndIsland(_, section, _, _), let .iconIslandPreview(_, section, _, _), let .stickerSizeSlider(_, section, _), let .stickerReplies(_, section, _), let .stickerPreview(_, section, _, _, _, _, _, _), let .stickerShape(_, section, _): return section
        }
    }
    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .toggle(id, _, _, _, _, _), let .disclosure(id, _, _, _, _), let .checkbox(id, _, _, _, _), let .info(id, _, _), let .input(id, _, _, _, _), let .messagePreview(id, _, _, _, _, _), let .chatListPreview(id, _, _, _, _, _, _), let .tabBarPreview(id, _, _),let .appIcons(id, _, _), let .islandStyles(id, _, _), let .speedSlider(id, _, _), let .iconAndIsland(id, _, _, _), let .iconIslandPreview(id, _, _, _), let .stickerSizeSlider(id, _, _), let .stickerReplies(id, _, _), let .stickerPreview(id, _, _, _, _, _, _, _), let .stickerShape(id, _, _): return id
        }
    }
    // The tag the row's node reports: the one item(presentationData:arguments:) gives the item,
    // or the fixed key of the speed slider and chat list preview nodes.
    var tag: ItemListItemTag? {
        switch self {
        case let .toggle(_, _, key, _, _, _), let .disclosure(_, _, key, _, _), let .checkbox(_, _, key, _, _), let .input(_, _, key, _, _): return DGSettingItemTag(key: key)
        case .iconAndIsland: return DGSettingItemTag(key: "iconAndIsland")
        case .speedSlider: return DGSettingItemTag(key: "downloadAcceleration")
        case .tabBarPreview: return DGSettingItemTag(key: "tabBarPreview")
        case .chatListPreview: return DGSettingItemTag(key: "chatListPreview")
        case .stickerSizeSlider: return DGSettingItemTag(key: "stickerSize")
        case .stickerReplies: return DGSettingItemTag(key: "stickerReplies")
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
        case let .checkbox(id, section, key, title, checked): return .checkbox(id, section, key, tr(title), checked)
        case let .info(id, section, text): return .info(id, section, tr(text))
        case let .input(id, section, key, value, placeholder): return .input(id, section, key, value, tr(placeholder))
        default: return self
        }
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! DGListArguments
        let languageCode = presentationData.strings.primaryComponent.languageCode
        func tr(_ text: String) -> String { dgLocalized(text, languageCode: languageCode) }
        func icon(_ key: String, _ title: String, enabled: Bool = true) -> UIImage? {
            let color = enabled ? presentationData.theme.list.itemPrimaryTextColor : presentationData.theme.list.itemDisabledTextColor
            return PresentationResourcesSettings.donutgramOutlineIcon(dgSettingsSymbol(key: key, title: title), color: color)
        }
        switch self {
        case let .header(_, _, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .toggle(_, _, key, title, value, enabled):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: icon(key, title, enabled: enabled), title: title, value: value, enableInteractiveChanges: enabled, enabled: enabled, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { arguments.toggle(key, $0) }, tag: DGSettingItemTag(key: key))
        case let .disclosure(_, _, key, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon(key, title), title: title, label: label, sectionId: self.section, style: .blocks, disclosureStyle: .arrow, action: { arguments.open(key) }, tag: DGSettingItemTag(key: key))
        case let .checkbox(_, _, key, title, checked):
            return ItemListCheckboxItem(presentationData: presentationData, systemStyle: .glass, title: title, style: .left, checked: checked, zeroSeparatorInsets: false, sectionId: self.section, action: { arguments.select(key) }, tag: DGSettingItemTag(key: key))
        case let .info(_, _, text):
            return ItemListTextItem(presentationData: presentationData, text: .markdown(text), sectionId: self.section)
        case let .input(_, _, key, value, placeholder):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(), text: value, placeholder: placeholder, type: key == "level" ? .number : .regular(capitalization: false, autocorrection: false), clearType: .always, tag: DGSettingItemTag(key: key), sectionId: self.section, textUpdated: { arguments.textUpdated(key, $0) }, action: {})
        case .messagePreview:
            return donutgramMessagePreviewItem(context: arguments.context, sectionId: self.section)
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
        case let .stickerPreview(_, _, _, _, _, _, _, sticker):
            return donutgramStickerPreviewItem(context: arguments.context, sectionId: self.section, sticker: sticker)
        case let .stickerReplies(_, _, options):
            let subItems = [(1, "Цвета"), (2, "Эмодзи"), (4, "Фон")].map { bit, title in
                ItemListExpandableSwitchItem.SubItem(id: bit, title: tr(title), isSelected: options & bit != 0, isEnabled: true)
            }
            return ItemListExpandableSwitchItem(presentationData: presentationData, systemStyle: .glass, title: tr("Ответы"), value: options != 0, isExpanded: false, subItems: subItems, sectionId: self.section, style: .blocks, updated: { arguments.toggle("stickerReplies", $0) }, selectAction: { arguments.open("stickerReplyOptions") }, subAction: { _ in }, tag: DGSettingItemTag(key: "stickerReplies"))
        case let .stickerShape(_, _, shape):
            return DGStickerAppearanceItem(theme: presentationData.theme, languageCode: languageCode, sectionId: self.section, shapePicker: true, size: DGSimpleSettings.shared.stickerSize, shape: shape, updated: { arguments.select($0) })
        case let .iconAndIsland(_, _, iconMark, islandMark):
            return donutgramIconAndIslandItem(presentationData: presentationData, sectionId: self.section, iconName: DGSimpleSettings.appMarks[iconMark].iconName, islandMark: islandMark, action: { arguments.open("iconAndIsland") }, tag: DGSettingItemTag(key: "iconAndIsland"))
        case let .iconIslandPreview(_, _, iconMark, islandMark):
            return DGIconIslandPreviewItem(theme: presentationData.theme, languageCode: languageCode, sectionId: self.section, icon: DGSimpleSettings.appMarks[iconMark], island: DGSimpleSettings.appMarks[islandMark])
        }
    }
}

func dgController(context: AccountContext, page: DGSettingsPage, title: String, focusKey: String?, entries: @escaping () -> [DGListEntry], restartRequiredKeys: Set<String> = [], additionalUpdates: Signal<Void, NoError> = .single(()), toggle: @escaping (String, Bool) -> Void = { _, _ in }, select: @escaping (String) -> Void = { _ in }, textUpdated: @escaping (String, String) -> Void = { _, _ in }, open: @escaping (String) -> ViewController? = { _ in nil }) -> ViewController {
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
        }
    }, textUpdated: { key, value in textUpdated(key, value) })
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

public func dgSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    return dgController(context: context, page: .root, title: "Настройки Donutgram", focusKey: focusKey, entries: {
        [.header(0, 0, "DONUTGRAM"), .disclosure(1, 0, "spy", "Основные", ""), .disclosure(2, 0, "downloads", "Скачивание", ""), .disclosure(3, 0, "chats", "Внешний вид", ""), .disclosure(4, 0, "appearance", "Оформление", ""), .disclosure(5, 0, "support", "Поддержка", "")]
    }, open: { key in
        switch key {
        case "downloads": return dgDownloadsSettingsController(context: context)
        case "spy": return dgSpySettingsController(context: context)
        case "chats": return dgChatsSettingsController(context: context)
        case "appearance": return dgAppearanceSettingsController(context: context)
        case "support": return dgSupportController(context: context)
        default: return nil
        }
    })
}
