import Foundation
import Display
import AccountContext
import DGSimpleSettings
import Postbox
import SwiftSignalKit
import TelegramUIPreferences
import TelegramCore
import SettingsUI
import PresentationDataUtils
import OverlayStatusController

/// The value picked in a row's menu: the options of the row «key» are selected as "key:value".
private func dgMenuChoice(_ selection: String, of key: String) -> String? {
    let prefix = key + ":"
    return selection.hasPrefix(prefix) ? String(selection.dropFirst(prefix.count)) : nil
}

private func dgUpdatedMask(_ mask: Int, bit: Int, isOn: Bool) -> Int {
    return isOn ? (mask | bit) : (mask & ~bit)
}

// MARK: - Приватность

func dgGhostSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    let silentTitles = ["Никогда", "В режиме призрака", "Всегда"]
    return dgController(context: context, page: .ghost, title: "Режим призрака", focusKey: focusKey, entries: {
        // What is not sent is checked together with the main switch, so without it those rows stay off and locked.
        let isOn = s.ghostModeEnabled
        var result: [DGListEntry] = [
            .toggle(1, 0, "enabled", "Режим призрака", isOn, true),
            .info(2, 0, "Собеседники не узнают, что вы прочитали сообщения, посмотрели истории или были в сети."),
            .header(10, 1, "НЕ ОТПРАВЛЯТЬ"),
            .toggle(11, 1, "messages", "Отметки о прочтении сообщений", isOn && !s.ghostReadMessages, isOn),
            .toggle(12, 1, "storyViews", "Отметки о просмотре историй", isOn && !s.ghostReadStories, isOn),
            .toggle(13, 1, "online", "Статус «онлайн»", isOn && !s.ghostSendOnline, isOn),
            .toggle(14, 1, "typing", "Статус «печатает»", isOn && !s.ghostSendTyping, isOn)
        ]
        if !isOn {
            result.append(.info(15, 1, "Параметры действуют только при включённом режиме призрака."))
        }
        let silent = silentTitles[min(max(s.ghostSendWithoutSound, 0), 2)]
        result.append(contentsOf: [
            .header(20, 2, "ПОВЕДЕНИЕ"),
            .toggle(21, 2, "offline", "Автоматический «офлайн»", isOn && s.ghostAutomaticOffline, isOn),
            .toggle(22, 2, "readOnAction", "Читать при действиях", s.ghostReadOnAction, isOn),
            .toggle(23, 2, "scheduled", "Использовать отложку", s.ghostUseScheduledMessages, isOn),
            .menu(24, 2, "silent", "Отправлять без звука", silent),
            .toggle(25, 2, "stories", "Предлагать призрака для сторис", s.ghostSuggestForStories, true),
            .header(30, 3, "ЧТЕНИЕ"),
            .action(31, 3, "readAll", "Прочитать все на сервере"),
            .action(32, 3, "readAllLocal", "Прочитать все локально")
        ])
        return result
    }, toggle: { key, value in
        switch key {
        case "enabled": s.ghostModeEnabled = value
        case "messages": s.ghostReadMessages = !value
        case "storyViews": s.ghostReadStories = !value
        case "online": s.ghostSendOnline = !value
        case "typing": s.ghostSendTyping = !value
        case "offline": s.ghostAutomaticOffline = value
        case "readOnAction": s.ghostReadOnAction = value
        case "scheduled": s.ghostUseScheduledMessages = value
        case "stories": s.ghostSuggestForStories = value
        default: break
        }
    }, select: { key in
        if let value = dgMenuChoice(key, of: "silent").flatMap({ Int($0) }) {
            s.ghostSendWithoutSound = value
        }
    }, menu: { key in
        guard key == "silent" else {
            return []
        }
        return silentTitles.enumerated().map { index, title in
            DGMenuOption(key: "silent:\(index)", title: title, isSelected: s.ghostSendWithoutSound == index)
        }
    }, perform: { key, controller in
        if key == "readAll" { dgPresentReadAllOnServer(context: context, controller: controller) }
        if key == "readAllLocal" { dgPresentReadAllLocally(context: context, controller: controller) }
    })
}

private func dgPresentReadAllLocally(context: AccountContext, controller: ViewController) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let languageCode = presentationData.strings.primaryComponent.languageCode
    controller.present(textAlertController(context: context, title: nil, text: dgLocalized("Прочитать все сообщения только на этом устройстве?", languageCode: languageCode), actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
        TextAlertAction(type: .defaultAction, title: dgLocalized("Прочитать", languageCode: languageCode), action: { [weak controller] in
            let progress = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
            controller?.present(progress, in: .window(.root))
            let _ = (context.engine.messages.donutgramReadAllMessagesLocally() |> deliverOnMainQueue).startStandalone(next: { [weak controller] _ in
                progress.dismiss()
                let text = dgLocalized("Все сообщения прочитаны", languageCode: languageCode)
                controller?.present(textAlertController(context: context, title: nil, text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
            })
        })
    ]), in: .window(.root))
}

private func dgPresentReadAllOnServer(context: AccountContext, controller: ViewController) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let languageCode = presentationData.strings.primaryComponent.languageCode
    controller.present(textAlertController(context: context, title: nil, text: dgLocalized("Прочитать все сообщения?", languageCode: languageCode), actions: [
        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
        TextAlertAction(type: .defaultAction, title: dgLocalized("Прочитать", languageCode: languageCode), action: { [weak controller] in
            let progress = OverlayStatusController(theme: presentationData.theme, type: .loading(cancelled: nil))
            controller?.present(progress, in: .window(.root))
            let _ = (context.engine.messages.donutgramReadAllMessagesOnServer() |> deliverOnMainQueue).startStandalone(next: { [weak controller] succeeded in
                progress.dismiss()
                let text = succeeded ? "Все сообщения прочитаны" : "Не удалось прочитать все сообщения. Попробуйте ещё раз."
                controller?.present(textAlertController(context: context, title: nil, text: dgLocalized(text, languageCode: languageCode), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
            })
        })
    ]), in: .window(.root))
}

func dgSavingSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .saving, title: "Сохранение", focusKey: focusKey, entries: {
        var result: [DGListEntry] = [.header(0, 0, "СООБЩЕНИЯ"), .toggle(1, 0, "saveDeleted", "Сохранять удаленки", s.saveDeletedMessages, true)]
        if s.saveDeletedMessages {
            result.append(.toggle(2, 0, "saveOwnDeleted", "Сохранять свои удаленки", s.saveOwnDeletedMessages, true))
        }
        // The look and the storage are shown with saving off as well: what was saved before stays until it is deleted.
        result.append(contentsOf: [
            .toggle(3, 0, "saveBots", "Сохранять в чатах с ботами", s.saveInBotChats, true),
            .toggle(4, 0, "transparentDeleted", "Полупрозрачные удаленки", s.semiTransparentDeletedMessages, true),
            .toggle(5, 0, "saveEdits", "Сохранять историю правок", s.saveEditHistory, true),
            .header(10, 1, "МЕДИА И ПРОЧЕЕ"),
            .toggle(11, 1, "saveOnce", "Сохранять одноразки", s.saveViewOnceMedia, true),
            .toggle(12, 1, "saveProtectedStories", "Сохранять запрещенные истории", s.saveProtectedStories, true),
            .toggle(13, 1, "disappearedGifts", "Видеть удаленные подарки", s.showDisappearedGifts, true),
            .toggle(14, 1, "keepBannedChats", "Обход бана в чатах", s.keepBannedChats, true),
            .header(20, 2, "ХРАНИЛИЩЕ"),
            .disclosure(21, 2, "savedDeleted", "Сохраненные удаленки", ""),
            .info(22, 2, "Сохраненные удаленки хранятся только на этом устройстве. Если выключить «Сохранять удаленки», уже сохраненные останутся.")
        ])
        return result
    }, toggle: { key, value in
        switch key {
        case "saveDeleted": s.saveDeletedMessages = value
        case "saveOwnDeleted": s.saveOwnDeletedMessages = value
        case "saveBots": s.saveInBotChats = value
        case "transparentDeleted": s.semiTransparentDeletedMessages = value
        case "saveEdits": s.saveEditHistory = value
        case "saveOnce": s.saveViewOnceMedia = value
        case "saveProtectedStories": s.saveProtectedStories = value
        case "disappearedGifts": s.showDisappearedGifts = value
        case "keepBannedChats": s.keepBannedChats = value
        default: break
        }
    }, open: { key in
        return key == "savedDeleted" ? dgSavedDeletedMessagesController(context: context) : nil
    })
}

/// What tg://bg/spy opens: the saving of deleted messages and edits, the feature the link is named after.
public func dgSpySettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    return dgSavingSettingsController(context: context, focusKey: focusKey)
}

func dgBypassSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .bypass, title: "Обход ограничений", focusKey: focusKey, entries: {
        let result: [DGListEntry] = [
            .toggle(1, 0, "bypassForward", "Пересылка из защищённых чатов", s.bypassForwardRestrictions, true),
            .toggle(2, 0, "protectedScreenshots", "Скриншоты в защищённых чатах", s.allowProtectedScreenshots, true),
            .toggle(3, 0, "gifUnlock", "Обход блокировок GIF", s.gifUnlock, true)
        ]
        return result
    }, toggle: { key, value in
        switch key {
        case "bypassForward": s.bypassForwardRestrictions = value
        case "protectedScreenshots": s.allowProtectedScreenshots = value
        case "gifUnlock": s.gifUnlock = value
        default: break
        }
    })
}

// MARK: - Интерфейс

func dgMainScreenSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    let titleModes: [DGSimpleSettings.ChatListTitleMode] = [.donutgram, .username, .nickname, .chats]
    return dgController(context: context, page: .mainScreen, title: "Главный экран", focusKey: focusKey, entries: {
        let result: [DGListEntry] = [
            .header(0, 0, "ЗАГОЛОВОК"),
            .chatListPreview(1, 0, s.forceSnow, s.chatListHideEmojiStatus, s.chatListCenteredTitle, s.chatListHideSearch, s.chatListTitleMode.rawValue),
            .menu(2, 0, "titleMode", "Текст в заголовке", dgChatListTitleModeTitle(s.chatListTitleMode)),
            .toggle(3, 0, "centerTitle", "Заголовок по центру", s.chatListCenteredTitle, true),
            .toggle(4, 0, "hideEmojiStatus", "Скрыть эмодзи-статус", s.chatListHideEmojiStatus, true),
            .toggle(5, 0, "hideStatus", "Скрыть статус соединения", s.chatListHideStatus, true),
            .header(10, 1, "СПИСОК ЧАТОВ"),
            .toggle(11, 1, "hideSearch", "Скрыть строку поиска", s.chatListHideSearch, true),
            .toggle(12, 1, "foldersAtBottom", "Папки внизу", s.chatListFoldersAtBottom, true),
            .toggle(13, 1, "hideArchive", "Скрывать архив из списка чатов", s.hideArchive, true),
            .toggle(14, 1, "hideStories", "Скрыть сторис", s.hideStories, true),
            .toggle(15, 1, "disableStoryCameraSwipe", "Отключить камеру по свайпу", s.disableStoryCameraSwipe, true),
            .header(20, 2, "ВКЛАДКИ"),
            .tabBarPreview(21, 2, s.tabBarLayout),
            .toggle(22, 2, "hideTabBar", "Скрыть панель вкладок", s.hideTabBar, true),
            .toggle(23, 2, "contacts", "Вкладка Контакты", s.showContactsTab, true),
            .toggle(24, 2, "calls", "Вкладка Звонки", s.showCallsTab, true),
            .toggle(25, 2, "wideTabBar", "Широкая Панель", s.wideTabBar, true)
        ]
        return result
    }, restartRequiredKeys: ["hideStories"], toggle: { key, value in
        switch key {
        case "centerTitle": s.chatListCenteredTitle = value
        case "hideEmojiStatus": s.chatListHideEmojiStatus = value
        case "hideStatus": s.chatListHideStatus = value
        case "hideSearch": s.chatListHideSearch = value
        case "foldersAtBottom": s.chatListFoldersAtBottom = value
        case "hideArchive": s.hideArchive = value
        case "hideStories": s.hideStories = value
        case "disableStoryCameraSwipe": s.disableStoryCameraSwipe = value
        case "hideTabBar": s.hideTabBar = value
        case "contacts": s.showContactsTab = value
        case "calls": s.showCallsTab = value
        case "wideTabBar": s.wideTabBar = value
        default: break
        }
    }, select: { key in
        if let value = dgMenuChoice(key, of: "titleMode").flatMap({ Int($0) }), let mode = DGSimpleSettings.ChatListTitleMode(rawValue: value) {
            s.chatListTitleMode = mode
        }
    }, menu: { key in
        guard key == "titleMode" else {
            return []
        }
        return titleModes.map { mode in
            DGMenuOption(key: "titleMode:\(mode.rawValue)", title: dgChatListTitleModeTitle(mode), isSelected: s.chatListTitleMode == mode)
        }
    })
}

private func dgChatListTitleModeTitle(_ mode: DGSimpleSettings.ChatListTitleMode) -> String {
    switch mode {
    case .donutgram: return "Donutgram"
    case .username: return "Юзернейм"
    case .nickname: return "Никнейм"
    case .chats: return "Чаты"
    }
}

/// The emoji the message previews show: none at first, then the first status emoji.
private func dgPreviewEmoji(context: AccountContext) -> Signal<TelegramMediaFile?, NoError> {
    let emoji = context.engine.stickers.loadedStickerPack(reference: .iconStatusEmoji, forceActualized: false)
    |> map { result -> TelegramMediaFile? in
        if case let .result(_, items, _) = result { return items.first?.file._parse() }
        return nil
    }
    return Signal<TelegramMediaFile?, NoError>.single(nil) |> then(emoji)
}

/// The sticker the sticker preview shows: none at first, then a saved or recent sticker of the account, or a greeting sticker.
private func dgPreviewSticker(context: AccountContext) -> Signal<TelegramMediaFile?, NoError> {
    let sticker: Signal<TelegramMediaFile?, NoError> = context.account.postbox.transaction { transaction -> TelegramMediaFile? in
        for entry in transaction.getOrderedListItems(collectionId: Namespaces.OrderedItemList.CloudSavedStickers) {
            if let file = entry.contents.get(SavedStickerItem.self)?.file._parse(), file.isSticker, !file.isPremiumSticker {
                return file
            }
        }
        for entry in transaction.getOrderedListItems(collectionId: Namespaces.OrderedItemList.CloudRecentStickers) {
            if let file = entry.contents.get(RecentMediaItem.self)?.media._parse(), file.isSticker, !file.isPremiumSticker {
                return file
            }
        }
        return nil
    }
    |> mapToSignal { file -> Signal<TelegramMediaFile?, NoError> in
        if let file { return .single(file) }
        return context.engine.stickers.randomGreetingSticker() |> map { $0?.file }
    }
    return Signal<TelegramMediaFile?, NoError>.single(nil) |> then(sticker)
}

func dgMessagesSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    var previewEmoji: TelegramMediaFile?
    let previewUpdates = dgPreviewEmoji(context: context)
    |> deliverOnMainQueue
    |> map { emoji -> Void in
        previewEmoji = emoji
    }
    return dgController(context: context, page: .messages, title: "Сообщения", focusKey: focusKey, entries: {
        let result: [DGListEntry] = [
            .header(0, 0, "ПУЗЫРИ"),
            .messagePreview(1, 0, s.messagePreviewConfiguration, previewEmoji),
            .toggle(2, 0, "tails", "Убрать хвост у сообщений", s.removeMessageTails, true),
            .toggle(3, 0, "seconds", "Показывать секунды", s.showMessageSeconds, true),
            .toggle(4, 0, "editedIcon", "Заменять «изменено» иконкой", s.editedIcon, true),
            .toggle(5, 0, "onlineIndicator", "Показывать индикатор онлайна", s.showOnlineIndicator, true),
            .toggle(6, 0, "customBackgrounds", "Отключить кастомные фоны", s.disableCustomBackgrounds, true),
            .header(10, 1, "ОТВЕТЫ И УПОМИНАНИЯ"),
            .toggle(11, 1, "replies", "Отключить цветные ответы", s.disableColoredReplies, true),
            .toggle(12, 1, "hidePremiumReplyEmoji", "Скрыть премиум эмодзи", s.hidePremiumReplyEmoji, true),
            .toggle(13, 1, "mentionComma", "Запятая после упоминания", s.commaAfterMention, true),
            .toggle(14, 1, "mentionAvatars", "Аватарки в упоминаниях", s.mentionAvatars, true),
            .toggle(15, 1, "removePings", "Убрать пинги", s.removePings, true),
            .header(20, 2, "СОДЕРЖИМОЕ"),
            .toggle(21, 2, "removeLinkPreviews", "Удалить превью-ссылки", s.removeLinkPreviews, true),
            .toggle(22, 2, "hideViaBot", "Скрыть «Via Bot» в сообщении", s.hideViaBot, true),
            .toggle(23, 2, "hideServiceMessages", "Отключить служебные сообщения", s.hideServiceMessages, true),
            .toggle(24, 2, "greetingSticker", "Скрыть приветственный стикер", s.hideGreetingSticker, true),
            .toggle(25, 2, "pollResultsBeforeVoting", "Итоги до голосования", s.showPollResultsBeforeVoting, true),
            .toggle(26, 2, "hideBotAutomation", "Скрыть автоматизацию ботов", s.hideBotAutomation, true),
            .header(30, 3, "ПЕРЕСЛАННЫЕ"),
            .toggle(31, 3, "forwardDate", "Время пересылки", s.showForwardDate, true),
            .toggle(32, 3, "channelForwardCount", "Счетчик пересылок в каналах", s.showChannelForwardCount, true),
            .header(40, 4, "КАНАЛЫ"),
            .toggle(41, 4, "wideChannelPosts", "Широкие посты в каналах", s.wideChannelPosts, true),
            .menu(42, 4, "channelBottomButton", "Нижняя кнопка", dgChannelBottomButtonTitle(s.channelBottomButton)),
            .info(43, 4, "«Обсудить» открывает группу обсуждения канала. В каналах без обсуждения кнопка скрыта."),
            .header(50, 5, "МЕНЮ АВАТАРКИ"),
            .toggle(51, 5, "jumpToStart", "Кнопка «В начало чата»", s.jumpToStartInChatMenu, true),
            .info(52, 5, "Появляется в меню, если зажать аватарку в чате, и переносит к самому первому сообщению.")
        ]
        return result
    }, additionalUpdates: previewUpdates, toggle: { key, value in
        switch key {
        case "tails": s.removeMessageTails = value
        case "seconds": s.showMessageSeconds = value
        case "editedIcon": s.editedIcon = value
        case "onlineIndicator": s.showOnlineIndicator = value
        case "customBackgrounds": s.disableCustomBackgrounds = value
        case "replies": s.disableColoredReplies = value
        case "hidePremiumReplyEmoji": s.hidePremiumReplyEmoji = value
        case "mentionComma": s.commaAfterMention = value
        case "mentionAvatars": s.mentionAvatars = value
        case "removePings": s.removePings = value
        case "removeLinkPreviews": s.removeLinkPreviews = value
        case "hideViaBot": s.hideViaBot = value
        case "hideServiceMessages": s.hideServiceMessages = value
        case "greetingSticker": s.hideGreetingSticker = value
        case "pollResultsBeforeVoting": s.showPollResultsBeforeVoting = value
        case "hideBotAutomation": s.hideBotAutomation = value
        case "forwardDate": s.showForwardDate = value
        case "channelForwardCount": s.showChannelForwardCount = value
        case "wideChannelPosts": s.wideChannelPosts = value
        case "jumpToStart": s.jumpToStartInChatMenu = value
        default: break
        }
    }, select: { key in
        if let value = dgMenuChoice(key, of: "channelBottomButton").flatMap({ Int($0) }), let button = DGSimpleSettings.ChannelBottomButton(rawValue: value) {
            s.channelBottomButton = button
        }
    }, menu: { key in
        guard key == "channelBottomButton" else {
            return []
        }
        return DGSimpleSettings.ChannelBottomButton.allCases.map { button in
            DGMenuOption(key: "channelBottomButton:\(button.rawValue)", title: dgChannelBottomButtonTitle(button), isSelected: s.channelBottomButton == button)
        }
    })
}

private func dgChannelBottomButtonTitle(_ value: DGSimpleSettings.ChannelBottomButton) -> String {
    switch value {
    case .discuss: return "Обсудить"
    case .mute: return "Убрать звук"
    case .hidden: return "Скрыть"
    }
}

func dgStickersSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    var previewSticker: TelegramMediaFile?
    var previewEmoji: TelegramMediaFile?
    let previewUpdates = combineLatest(dgPreviewSticker(context: context), dgPreviewEmoji(context: context))
    |> deliverOnMainQueue
    |> map { sticker, emoji -> Void in
        previewSticker = sticker
        previewEmoji = emoji
    }
    return dgController(context: context, page: .stickers, title: "Стикеры и реакции", focusKey: focusKey, entries: {
        let hiddenReactions = s.hiddenReactions
        let result: [DGListEntry] = [
            .header(0, 0, "СТИКЕРЫ"),
            .stickerSizeSlider(1, 0, s.stickerSize),
            .stickerPreview(2, 0, s.stickerSize, s.hideStickerTime, s.hideStickerChecks, s.stickerReplyOptions, s.stickerShape, s.messagePreviewConfiguration, previewSticker, previewEmoji),
            .toggle(3, 0, "hideStickerTime", "Скрыть время на стикерах", s.hideStickerTime, true),
            .toggle(4, 0, "hideStickerChecks", "Скрыть галочки на стикерах", s.hideStickerChecks, true),
            .toggle(5, 0, "hideStickerReplyColors", "Скрыть цвета", s.hideStickerReplyColors, true),
            .toggle(6, 0, "hideStickerReplyEmoji", "Скрыть эмодзи", s.hideStickerReplyEmoji, true),
            .toggle(7, 0, "hideStickerReplyBackground", "Скрыть фон", s.hideStickerReplyBackground, true),
            .header(10, 1, "ФОРМА СТИКЕРОВ"),
            .stickerShape(11, 1, s.stickerShape),
            .header(20, 2, "ПАНЕЛЬ СТИКЕРОВ"),
            .toggle(21, 2, "onlyAdded", "Показывать только добавленные стикеры", s.onlyAddedStickers, true),
            .toggle(22, 2, "recent", "Беск. недавние стикеры", s.infiniteRecentStickers, true),
            .header(30, 3, "РЕАКЦИИ"),
            .toggle(31, 3, "reactionsInChannels", "Скрыть реакции в каналах", hiddenReactions & 1 != 0, true),
            .toggle(32, 3, "reactionsInGroups", "Скрыть реакции в группах", hiddenReactions & 2 != 0, true),
            .toggle(33, 3, "reactionsInPrivateChats", "Скрыть реакции в личных чатах", hiddenReactions & 4 != 0, true),
            .toggle(34, 3, "hidePaidReactions", "Скрыть платные реакции", s.hidePaidReactions, true)
        ]
        return result
    }, additionalUpdates: previewUpdates, toggle: { key, value in
        switch key {
        case "hideStickerTime": s.hideStickerTime = value
        case "hideStickerChecks": s.hideStickerChecks = value
        case "hideStickerReplyColors": s.hideStickerReplyColors = value
        case "hideStickerReplyEmoji": s.hideStickerReplyEmoji = value
        case "hideStickerReplyBackground": s.hideStickerReplyBackground = value
        case "onlyAdded": s.onlyAddedStickers = value
        case "recent": s.infiniteRecentStickers = value
        case "reactionsInChannels": s.hiddenReactions = dgUpdatedMask(s.hiddenReactions, bit: 1, isOn: value)
        case "reactionsInGroups": s.hiddenReactions = dgUpdatedMask(s.hiddenReactions, bit: 2, isOn: value)
        case "reactionsInPrivateChats": s.hiddenReactions = dgUpdatedMask(s.hiddenReactions, bit: 4, isOn: value)
        case "hidePaidReactions": s.hidePaidReactions = value
        default: break
        }
    }, select: { key in
        if key == "resetStickerAppearance" {
            s.stickerSize = 11
            s.hideStickerTime = false
            s.hideStickerChecks = false
            s.stickerReplyOptions = 7
            s.stickerShape = 0
        } else if let value = Int(key.split(separator: ":").last ?? "") {
            if key.hasPrefix("stickerSize:") { s.stickerSize = value }
            else if key.hasPrefix("stickerShape:") { s.stickerShape = value }
        }
    })
}

func dgProfilesSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .profiles, title: "Профили", focusKey: focusKey, entries: {
        var result: [DGListEntry] = [.header(0, 0, "ИНФОРМАЦИЯ"), .toggle(1, 0, "profileId", "ID Профилей", s.showProfileId, true)]
        if s.showProfileId {
            result.append(.menu(2, 0, "dialogIdFormat", "Показывать ID диалога", s.dialogIdFormat == .botApi ? "Bot API" : "Telegram API"))
        }
        result.append(contentsOf: [
            .toggle(3, 0, "dc", "Показывать дата-центр (DC)", s.showDc, true),
            .toggle(4, 0, "regDate", "Показывать дату регистрации", s.showRegistrationDate, true),
            .toggle(5, 0, "chatDate", "Показывать дату создания чата", s.showChatCreationDate, true),
            .toggle(6, 0, "mutualContact", "Показывать взаимный контакт", s.showMutualContact, true),
            .toggle(7, 0, "relativeOnlineTime", "Относительное время онлайна", s.relativeOnlineTime, true),
            .toggle(8, 0, "hidePhoneNumber", "Скрыть номер телефона", s.hidePhoneNumber, true),
            .header(10, 1, "ЗНАЧКИ У ИМЁН"),
            .toggle(11, 1, "premiumStatuses", "Скрыть премиум статусы", s.hidePremiumStatuses, true),
            .toggle(12, 1, "hideVerification", "Скрыть верификацию", s.hideVerification, true)
        ])
        return result
    }, restartRequiredKeys: ["premiumStatuses", "hideVerification"], toggle: { key, value in
        switch key {
        case "profileId": s.showProfileId = value
        case "dc": s.showDc = value
        case "regDate": s.showRegistrationDate = value
        case "chatDate": s.showChatCreationDate = value
        case "mutualContact": s.showMutualContact = value
        case "relativeOnlineTime": s.relativeOnlineTime = value
        case "hidePhoneNumber": s.hidePhoneNumber = value
        case "premiumStatuses": s.hidePremiumStatuses = value
        case "hideVerification": s.hideVerification = value
        default: break
        }
    }, select: { key in
        if let value = dgMenuChoice(key, of: "dialogIdFormat") {
            s.dialogIdFormat = value == "1" ? .botApi : .telegramApi
        }
    }, menu: { key in
        guard key == "dialogIdFormat" else {
            return []
        }
        return [
            DGMenuOption(key: "dialogIdFormat:0", title: "Telegram API", isSelected: s.dialogIdFormat == .telegramApi),
            DGMenuOption(key: "dialogIdFormat:1", title: "Bot API", isSelected: s.dialogIdFormat == .botApi)
        ]
    })
}

func dgIconAndEffectsSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .iconAndEffects, title: "Иконка и эффекты", focusKey: focusKey, entries: {
        let result: [DGListEntry] = [
            .header(0, 0, "ПРИЛОЖЕНИЕ"),
            dgIconAndIslandRow(context: context, id: 1, section: 0),
            .header(10, 1, "ЭФФЕКТЫ"),
            .toggle(11, 1, "snow", "Снег", s.forceSnow, true),
            .toggle(12, 1, "avatarGlow", "Свечение аватарок", s.avatarGlow, true),
            .toggle(13, 1, "reactionGlow", "Свечение реакций", s.reactionGlow, true)
        ]
        return result
    }, toggle: { key, value in
        switch key {
        case "snow": s.forceSnow = value
        case "avatarGlow": s.avatarGlow = value
        case "reactionGlow": s.reactionGlow = value
        default: break
        }
    }, open: { key in
        return key == "iconAndIsland" ? dgIconAndIslandController(context: context) : nil
    })
}

/// The row that opens «Иконка и остров», the same row as in the stock appearance settings.
private func dgIconAndIslandRow(context: AccountContext, id: Int32, section: Int32) -> DGListEntry {
    let iconName = context.sharedContext.applicationBindings.getAlternateIconName()
    return .iconAndIsland(id, section, DGSimpleSettings.appMarkIndex(iconName: iconName), DGSimpleSettings.shared.islandMarkIndex(iconName: iconName))
}

/// «Иконка и остров»: the app icon, the island under the notch or the Dynamic Island, and «Остров как у иконки».
/// Devices without a notch or an island (iPad, iPhones with a Home button) get the icon picker alone.
/// Also opened from the stock appearance settings and the «Иконка приложения» home screen quick action.
public func dgIconAndIslandController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    let bindings = context.sharedContext.applicationBindings
    let hasIsland = DeviceMetrics.deviceHasAppBadge
    return dgController(context: context, page: .iconAndIsland, title: donutgramIconAndIslandTitle(), focusKey: focusKey, entries: {
        let iconName = bindings.getAlternateIconName()
        var entries: [DGListEntry] = []
        if hasIsland {
            entries.append(contentsOf: [
                .header(0, 0, "ПРЕДПРОСМОТР"),
                .iconIslandPreview(1, 0, DGSimpleSettings.appMarkIndex(iconName: iconName), s.islandMarkIndex(iconName: iconName)),
                .toggle(10, 1, "islandFollowsIcon", "Остров как у иконки", s.islandFollowsIcon, true)
            ])
            if !s.islandFollowsIcon {
                // The islands join the switch's block: turning it off shows them right under the finger, next to the
                // preview, instead of below the six rows of icons.
                entries.append(contentsOf: [.islandStyles(11, 1, s.islandStyle), .info(12, 1, "Иконка и остров выбираются отдельно.")])
            }
        }
        entries.append(contentsOf: [.header(20, 2, "ИКОНКА"), .appIcons(21, 2, DGSimpleSettings.appMarkIndex(iconName: iconName))])
        return entries
    }, toggle: { key, value in
        guard key == "islandFollowsIcon" else {
            return
        }
        if !value {
            // The island on screen stays: it becomes the one picked by hand.
            s.islandStyle = DGSimpleSettings.appMarkIndex(iconName: bindings.getAlternateIconName())
        }
        s.islandFollowsIcon = value
        dgApplyIslandBadge(context: context)
    }, select: { key in
        if key.hasPrefix("islandStyle:"), let value = Int(key.split(separator: ":").last ?? "") {
            s.islandStyle = value
            dgApplyIslandBadge(context: context)
        }
    })
}

// MARK: - Медиа и сеть

private func dgRoundVideoCameraTitle(_ camera: DGSimpleSettings.RoundVideoCamera) -> String {
    switch camera {
    case .front: return "Фронтальная"
    case .rear: return "Основная"
    case .ask: return "Спрашивать"
    }
}

private func dgTranscriptionBackendTitle(_ backend: DGSimpleSettings.TranscriptionBackend) -> String {
    switch backend {
    case .auto: return "Авто"
    case .telegram: return "Telegram"
    case .apple: return "Apple"
    }
}

private func dgTranscriptionBackendInfo(_ backend: DGSimpleSettings.TranscriptionBackend) -> String {
    switch backend {
    case .auto: return "Telegram, пока он может расшифровать сообщение сам — с Premium или бесплатными попытками. Иначе Apple."
    case .telegram: return "Telegram использует облачный сервис распознавания."
    case .apple: return "Apple распознаёт речь на устройстве, а если язык не поддерживается — на серверах Apple."
    }
}

func dgMediaSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    let cameras: [DGSimpleSettings.RoundVideoCamera] = [.front, .rear, .ask]
    let seekValues = [0, 5, 10, 15, 30]
    let backends: [DGSimpleSettings.TranscriptionBackend] = [.auto, .telegram, .apple]
    // The switches say whether music pauses; the setting keeps the cases where it does not.
    let musicPauses: [String: DGSimpleSettings.MusicPlaybackExceptions] = [
        "pauseMusicRoundVideos": .roundVideos,
        "pauseMusicVoiceRecording": .voiceRecording,
        "pauseMusicVoicePlayback": .voicePlayback
    ]
    return dgController(context: context, page: .media, title: "Запись и воспроизведение", focusKey: focusKey, entries: {
        let exceptions = s.musicPlaybackExceptions
        let seek = s.doubleTapSeekSeconds == 0 ? "Отключено" : "\(s.doubleTapSeekSeconds) сек."
        var result: [DGListEntry] = [
            .header(0, 0, "КРУЖКИ"),
            .menu(1, 0, "camera", "Камера в кружках", dgRoundVideoCameraTitle(s.roundVideoCamera)),
            .toggle(2, 0, "rememberCamera", "Запоминать последнюю камеру", s.rememberRoundVideoCamera, true),
            .toggle(3, 0, "zoomSlider", "Слайдер зума", s.roundVideoZoomSlider, true),
            .toggle(4, 0, "staticZoom", "Оставлять зум после щипка", s.staticRoundVideoZoom, true),
            .toggle(5, 0, "builtInMic", "Встроенный микрофон", s.forceBuiltInMicrophone, true),
            .header(10, 1, "ПАУЗА МУЗЫКИ"),
            .toggle(11, 1, "pauseMusicRoundVideos", "При записи кружков", !exceptions.contains(.roundVideos), true),
            .toggle(12, 1, "pauseMusicVoiceRecording", "При записи голосовых", !exceptions.contains(.voiceRecording), true),
            .toggle(13, 1, "pauseMusicVoicePlayback", "При прослушивании голосовых", !exceptions.contains(.voicePlayback), true),
            .info(14, 1, "Если выключить, музыка продолжит играть."),
            .header(20, 2, "ВОСПРОИЗВЕДЕНИЕ"),
            .menu(21, 2, "doubleTapSeek", "Перемотка двойным нажатием", seek),
            .header(30, 3, "АВТОПАУЗА"),
            .toggle(31, 3, "autoPause", "Автопауза", s.autoPause, true)
        ]
        if s.autoPause {
            let paused = s.autoPauseMedia
            result.append(contentsOf: [
                .toggle(32, 3, "autoPauseVideo", "Видео", paused & 1 != 0, true),
                .toggle(33, 3, "autoPauseVoice", "Голосовые", paused & 2 != 0, true),
                .toggle(34, 3, "autoPauseRound", "Кружки", paused & 4 != 0, true)
            ])
        }
        result.append(contentsOf: [
            .info(35, 3, "Ставит на паузу, когда вы сворачиваете приложение или блокируете экран."),
            .header(40, 4, "АВТОВОСПРОИЗВЕДЕНИЕ"),
            .toggle(41, 4, "autoplayMedia", "Отключить автовоспроизведение медиа", s.disableMediaAutoplay, true)
        ])
        if s.disableMediaAutoplay {
            let stopped = s.disabledAutoplayMediaTypes
            result.append(contentsOf: [
                .toggle(42, 4, "autoplayVoice", "Голосовые", stopped & 1 != 0, true),
                .toggle(43, 4, "autoplayRound", "Кружки", stopped & 2 != 0, true)
            ])
        }
        result.append(contentsOf: [
            .info(44, 4, "Если включено, следующее ГС или кружок не запустится автоматически."),
            .header(50, 5, "ГОЛОС В ТЕКСТ"),
            .menu(51, 5, "transcription", "Сервис", dgTranscriptionBackendTitle(s.transcriptionBackend)),
            .info(52, 5, dgTranscriptionBackendInfo(s.transcriptionBackend))
        ])
        return result
    }, toggle: { key, value in
        if let option = musicPauses[key] {
            if value {
                s.musicPlaybackExceptions.remove(option)
            } else {
                s.musicPlaybackExceptions.insert(option)
            }
            return
        }
        switch key {
        case "rememberCamera": s.rememberRoundVideoCamera = value
        case "zoomSlider": s.roundVideoZoomSlider = value
        case "staticZoom": s.staticRoundVideoZoom = value
        case "builtInMic": s.forceBuiltInMicrophone = value
        case "autoPause": s.autoPause = value
        case "autoPauseVideo": s.autoPauseMedia = dgUpdatedMask(s.autoPauseMedia, bit: 1, isOn: value)
        case "autoPauseVoice": s.autoPauseMedia = dgUpdatedMask(s.autoPauseMedia, bit: 2, isOn: value)
        case "autoPauseRound": s.autoPauseMedia = dgUpdatedMask(s.autoPauseMedia, bit: 4, isOn: value)
        case "autoplayMedia": s.disableMediaAutoplay = value
        case "autoplayVoice": s.disabledAutoplayMediaTypes = dgUpdatedMask(s.disabledAutoplayMediaTypes, bit: 1, isOn: value)
        case "autoplayRound": s.disabledAutoplayMediaTypes = dgUpdatedMask(s.disabledAutoplayMediaTypes, bit: 2, isOn: value)
        default: break
        }
    }, select: { key in
        if let value = dgMenuChoice(key, of: "camera").flatMap({ Int($0) }), let camera = DGSimpleSettings.RoundVideoCamera(rawValue: value) {
            s.roundVideoCamera = camera
        } else if let value = dgMenuChoice(key, of: "doubleTapSeek").flatMap({ Int($0) }) {
            s.doubleTapSeekSeconds = value
        } else if let value = dgMenuChoice(key, of: "transcription"), let backend = DGSimpleSettings.TranscriptionBackend(rawValue: value) {
            s.transcriptionBackend = backend
        }
    }, menu: { key in
        switch key {
        case "camera":
            return cameras.map { camera in
                DGMenuOption(key: "camera:\(camera.rawValue)", title: dgRoundVideoCameraTitle(camera), isSelected: s.roundVideoCamera == camera)
            }
        case "doubleTapSeek":
            return seekValues.map { value in
                DGMenuOption(key: "doubleTapSeek:\(value)", title: value == 0 ? "Отключено" : "\(value) секунд", isSelected: s.doubleTapSeekSeconds == value)
            }
        case "transcription":
            return backends.map { backend in
                DGMenuOption(key: "transcription:\(backend.rawValue)", title: dgTranscriptionBackendTitle(backend), isSelected: s.transcriptionBackend == backend)
            }
        default:
            return []
        }
    })
}

func dgDownloadsSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .downloads, title: "Загрузки и сеть", focusKey: focusKey, entries: {
        let result: [DGListEntry] = [
            .header(0, 0, "СКАЧИВАНИЕ"),
            .toggle(1, 0, "downloadTikTok", "Скачивать TikTok", s.downloadTikTok, true),
            .toggle(2, 0, "downloadShorts", "Скачивать YT Shorts", s.downloadYouTubeShorts, true),
            .toggle(3, 0, "signDownloads", "Подписывать", s.signDownloadedMedia, true),
            .info(4, 0, "Если TikTok не отдаёт видео или фото, они запрашиваются через сторонний сервис tikwm.com: он видит ссылку на пост и ваш IP-адрес."),
            .header(10, 1, "УСКОРЕНИЕ ЗАГРУЗКИ"),
            .speedSlider(11, 1, s.downloadAcceleration),
            .toggle(12, 1, "accelerateUpload", "Ускорение отправки", s.accelerateUpload, true),
            .info(13, 1, "Ультра использует больше одновременных соединений. На медленном интернете это может мешать загрузке файлов и просмотру видео.")
        ]
        return result
    }, toggle: { key, value in
        switch key {
        case "downloadTikTok": s.downloadTikTok = value
        case "downloadShorts": s.downloadYouTubeShorts = value
        case "signDownloads": s.signDownloadedMedia = value
        case "accelerateUpload": s.accelerateUpload = value
        default: break
        }
    }, select: { key in
        if key.hasPrefix("downloadAcceleration:"), let value = Int(key.split(separator: ":").last ?? "") { s.downloadAcceleration = value }
    })
}

// MARK: - Прочее

func dgSecuritySettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .security, title: "Безопасность", focusKey: focusKey, entries: {
        let result: [DGListEntry] = [
            .header(0, 0, "ПОДТВЕРЖДЕНИЯ"),
            .toggle(1, 0, "confirmCalls", "Подтверждение вызова", s.confirmCalls, true),
            .toggle(2, 0, "confirmReactionsInUnjoinedChats", "Подтверждать реакции без вступления", s.confirmReactionsInUnjoinedChats, true),
            .toggle(3, 0, "confirmTelegramLinks", "Подтверждать переход по ссылкам Telegram", s.confirmTelegramLinks, true),
            .toggle(4, 0, "confirmChatPreviewEntry", "Подтверждать вход из предпросмотра", s.confirmChatPreviewEntry, true),
            .header(10, 1, "СТАТИСТИКА"),
            .toggle(11, 1, "telegramStatistics", "Отправлять статистику в Telegram", s.sendTelegramStatistics, true),
            .info(12, 1, "Аналитика приложения, время чтения постов в каналах, прослушанная музыка, служебные логи и данные о качестве звонков, как в обычном Telegram. Сетевая телеметрия не отправляется никогда.")
        ]
        return result
    }, toggle: { key, value in
        switch key {
        case "confirmCalls": s.confirmCalls = value
        case "confirmReactionsInUnjoinedChats": s.confirmReactionsInUnjoinedChats = value
        case "confirmTelegramLinks": s.confirmTelegramLinks = value
        case "confirmChatPreviewEntry": s.confirmChatPreviewEntry = value
        case "telegramStatistics": s.sendTelegramStatistics = value
        default: break
        }
    })
}

func dgAdsAndGiftsSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .adsAndGifts, title: "Реклама и подарки", focusKey: focusKey, entries: {
        let result: [DGListEntry] = [
            .header(0, 0, "РЕКЛАМА"),
            .toggle(1, 0, "disableAds", "Отключить рекламу", s.disableAds, true),
            .header(10, 1, "ПОДАРКИ"),
            .toggle(11, 1, "hideGiftButton", "Скрыть отправку подарка", s.hideGiftButton, true),
            .toggle(12, 1, "hideBirthdayNotifications", "Скрыть уведомление о дне рождении", s.hideBirthdayNotifications, true),
            .toggle(13, 1, "disableGiftStarsRedirect", "Не открывать звёзды после продажи подарка", s.disableGiftStarsRedirect, true)
        ]
        return result
    }, toggle: { key, value in
        switch key {
        case "disableAds": s.disableAds = value
        case "hideGiftButton": s.hideGiftButton = value
        case "hideBirthdayNotifications": s.hideBirthdayNotifications = value
        case "disableGiftStarsRedirect": s.disableGiftStarsRedirect = value
        default: break
        }
    })
}

func dgLocalProfileSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    let accountId = context.account.peerId.toInt64()
    return dgController(context: context, page: .localProfile, title: "Локальный профиль", focusKey: focusKey, entries: {
        let phone = s.visualPhoneEnabled ? (s.visualPhoneNumber.isEmpty ? "Включен" : s.visualPhoneNumber) : "Выключен"
        let rating = s.visualRatingLevel(accountId: accountId).map { String($0) } ?? "Выключен"
        let profileId = s.visualProfileId(accountId: accountId)
        let premium = s.localPremium(accountId: accountId)
        var result: [DGListEntry] = [
            .header(0, 0, "ПРОФИЛЬ"),
            .disclosure(1, 0, "visualPhone", "Визуальный номер", phone),
            .disclosure(2, 0, "visualRating", "Визуальный рейтинг", rating),
            .disclosure(3, 0, "visualUsernames", "Визуальные NFT-юзернеймы", "\(s.visualUsernames(accountId: accountId).count)"),
            .disclosure(4, 0, "visualId", "Визуальный ID", profileId.isEmpty ? "Выключен" : profileId),
            .disclosure(5, 0, "visualLabel", "Визуальная метка", s.visualLabel(accountId: accountId).title),
            .toggle(6, 0, "localPremium", "Локальный TG Premium", premium, true)
        ]
        if premium {
            result.append(.info(7, 0, "Premium включён локально для этого аккаунта. Цвета папок и теги чатов настраиваются в разделе «Папки с чатами» и сохраняются только на этом устройстве. Сервер Telegram по-прежнему проверяет подписку для платных возможностей."))
        } else {
            result.append(.info(7, 0, "Меняется только то, что видите вы на этом устройстве. Собеседники видят ваш настоящий профиль."))
        }
        return result
    }, restartRequiredKeys: ["localPremium"], toggle: { key, value in
        if key == "localPremium" { s.setLocalPremium(value, accountId: accountId) }
    }, open: { key in
        switch key {
        case "visualPhone": return dgVisualPhoneController(context: context)
        case "visualRating": return dgVisualRatingController(context: context)
        case "visualUsernames": return dgVisualUsernamesController(context: context)
        case "visualId": return dgVisualIdController(context: context)
        case "visualLabel": return dgVisualLabelController(context: context)
        default: return nil
        }
    })
}

private func dgVisualLabelController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let settings = DGSimpleSettings.shared
    let accountId = context.account.peerId.toInt64()
    return dgController(context: context, page: .visualLabel, title: "Визуальная метка", focusKey: focusKey, entries: {
        var entries: [DGListEntry] = [.header(0, 0, "МЕТКА ПРОФИЛЯ")]
        for (index, label) in DGVisualLabel.allCases.enumerated() {
            entries.append(.checkbox(Int32(index + 1), 0, label.rawValue, label.title, settings.visualLabel(accountId: accountId) == label))
        }
        return entries
    }, select: { key in
        settings.setVisualLabel(DGVisualLabel(rawValue: key) ?? .none, accountId: accountId)
    })
}

private func dgVisualIdController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let settings = DGSimpleSettings.shared
    let accountId = context.account.peerId.toInt64()
    return dgController(context: context, page: .visualId, title: "Визуальный ID", focusKey: focusKey, entries: {
        [.header(0, 0, "ID ПРОФИЛЯ"), .input(1, 0, "visualId", settings.visualProfileId(accountId: accountId), "Любой текст"), .info(2, 0, "Меняется только ID в вашем профиле на этом устройстве. Пустое поле возвращает настоящий ID. Нажатие на ID копирует настоящий номер Telegram.")]
    }, textUpdated: { key, value in
        if key == "visualId" { settings.setVisualProfileId(value, accountId: accountId) }
    })
}

private func dgVisualRatingController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let settings = DGSimpleSettings.shared
    let accountId = context.account.peerId.toInt64()
    return dgController(context: context, page: .visualRating, title: "Визуальный рейтинг", focusKey: focusKey, entries: {
        [.header(0, 0, "УРОВЕНЬ"), .input(1, 0, "level", settings.visualRatingLevel(accountId: accountId).map { String($0) } ?? "", "1–100"), .info(2, 0, "Укажите уровень от 1 до 100. Значок и его узор выбираются тем же компонентом, что и в Telegram. Пустое поле возвращает реальный рейтинг. Изменение видно только в Donutgram на этом устройстве.")]
    }, textUpdated: { key, value in
        if key == "level" { settings.setVisualRatingLevel(Int(value), accountId: accountId) }
    })
}

private func dgVisualUsernamesController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let settings = DGSimpleSettings.shared
    let accountId = context.account.peerId.toInt64()
    return dgController(context: context, page: .visualUsernames, title: "Визуальные NFT-юзернеймы", focusKey: focusKey, entries: {
        [.header(0, 0, "ИМЕНА ЧЕРЕЗ ЗАПЯТУЮ"), .input(1, 0, "names", settings.visualUsernames(accountId: accountId).map { "@\($0.name)" }.joined(separator: ", "), "@username, @username2"), .info(2, 0, "Имена добавляются только локально. Активность и порядок меняются в редакторе имён. Карточка Telegram покажет дату добавления и условную цену от 9 TON. Реальные ссылки, владельцы и данные Telegram не меняются.")]
    }, textUpdated: { key, value in
        if key == "names" { settings.updateVisualUsernames(value, accountId: accountId) }
    })
}

private func dgVisualPhoneController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .visualPhone, title: "Визуальный номер", focusKey: focusKey, entries: {
        [.header(0, 0, "ПОДМЕНА НОМЕРА"), .toggle(1, 0, "enabled", "Показывать другой номер", s.visualPhoneEnabled, true), .input(2, 0, "number", s.visualPhoneNumber, "+888 0156 2794"), .info(3, 0, "Меняется только отображение номера в вашем профиле на этом устройстве. Реальный номер Telegram и данные аккаунта остаются прежними.")]
    }, toggle: { key, value in
        if key == "enabled" { s.visualPhoneEnabled = value }
    }, textUpdated: { key, value in
        if key == "number" { s.visualPhoneNumber = value }
    })
}

func dgAboutController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
    let version = build.isEmpty ? dgAppVersion() : "\(dgAppVersion()) (\(build))"
    return dgController(context: context, page: .about, title: "О Donutgram", focusKey: focusKey, entries: {
        let result: [DGListEntry] = [
            .header(0, 0, "DONUTGRAM"),
            .value(1, 0, "version", "Версия", version),
            .info(2, 0, "Раздел подготовлен для ссылок на поддержку и информацию о Donutgram.")
        ]
        return result
    })
}

// MARK: - Ссылки

public func dgSettingsControllerForLink(context: AccountContext, page: String, key: String) -> ViewController? {
    guard let page = DGSettingsPage(rawValue: page) else {
        return nil
    }
    let (target, row) = dgCurrentRowLocation(page: page, key: key)
    return dgPageController(target, context: context, focusKey: dgShownRow(page: target, key: row))
}

/// Where the row of a link lives now. Links name the page the row was on when they were copied.
private func dgCurrentRowLocation(page: DGSettingsPage, key: String) -> (DGSettingsPage, String) {
    switch page {
    case .root:
        // The rows of the old root lead to the sections that took their place.
        let sections = ["spy": "ghost", "chats": "messages", "appearance": "mainScreen", "support": "about"]
        return (.root, sections[key] ?? key)
    case .general, .appearance, .chats:
        return dgMovedRowLocation(key: key)
    case .ghost:
        return (.ghost, key == "options" ? "messages" : key)
    case .ghostOptions:
        return (.ghost, key == "stories" ? "storyViews" : key)
    case .silent:
        return (.ghost, "silent")
    case .dialogId:
        return (.profiles, "dialogIdFormat")
    case .channelBottomButton:
        return (.messages, "channelBottomButton")
    case .glow:
        return (.iconAndEffects, key == "reactionGlow" ? "reactionGlow" : "avatarGlow")
    case .stickerReplies:
        return (.stickers, "hideStickerReplyColors")
    case .chatListAppearance:
        return (.mainScreen, "chatListPreview")
    case .chatListTitle:
        return (.mainScreen, "titleMode")
    case .doubleTapSeek:
        return (.media, "doubleTapSeek")
    case .camera:
        return (.media, "camera")
    case .transcription:
        return (.media, "transcription")
    case .autoPause:
        // The keys of the old page were the media bits.
        return (.media, ["1": "autoPauseVideo", "2": "autoPauseVoice", "4": "autoPauseRound"][key] ?? "autoPause")
    case .autoplayMedia:
        return (.media, ["1": "autoplayVoice", "2": "autoplayRound"][key] ?? "autoplayMedia")
    case .musicPlaybackExceptions:
        return (.media, ["1": "pauseMusicRoundVideos", "2": "pauseMusicVoiceRecording", "4": "pauseMusicVoicePlayback"][key] ?? "pauseMusicRoundVideos")
    case .reactions:
        return (.stickers, ["1": "reactionsInChannels", "2": "reactionsInGroups", "4": "reactionsInPrivateChats"][key] ?? "reactionsInChannels")
    case .support:
        return (.about, key)
    case .saving, .bypass, .shadowBan, .mainScreen, .messages, .stickers, .profiles, .iconAndEffects, .media, .downloads, .security, .adsAndGifts, .localProfile, .about, .iconAndIsland, .visualId, .visualRating, .visualUsernames, .visualPhone, .visualLabel, .savedDeleted:
        return (page, key)
    }
}

/// The section a row of the old «Основные», «Оформление» or «Внешний вид» moved to. Their keys never overlapped.
private func dgMovedRowLocation(key: String) -> (DGSettingsPage, String) {
    switch key {
    case "ghost", "shadowBan":
        return (.root, key)
    case "saveDeleted", "saveOwnDeleted", "transparentDeleted", "savedDeleted", "saveEdits", "saveOnce", "saveBots", "disappearedGifts", "saveProtectedStories", "keepBannedChats":
        return (.saving, key)
    case "gifUnlock", "bypassForward", "protectedScreenshots":
        return (.bypass, key)
    case "chatListPreview", "titleMode", "centerTitle", "hideEmojiStatus", "hideStatus", "hideSearch", "foldersAtBottom", "hideArchive", "hideStories", "disableStoryCameraSwipe", "tabBarPreview", "hideTabBar", "contacts", "calls", "wideTabBar":
        return (.mainScreen, key)
    case "openArchiveOnPull":
        // Links to rows that are gone lead to the switches that replaced them.
        return (.mainScreen, "hideArchive")
    case "chatListAppearance":
        return (.mainScreen, "chatListPreview")
    case "tails", "seconds", "editedIcon", "onlineIndicator", "customBackgrounds", "replies", "hidePremiumReplyEmoji", "mentionComma", "mentionAvatars", "removePings", "removeLinkPreviews", "hideViaBot", "hideServiceMessages", "greetingSticker", "pollResultsBeforeVoting", "hideBotAutomation", "forwardDate", "channelForwardCount", "wideChannelPosts", "channelBottomButton", "jumpToStart":
        return (.messages, key)
    case "stickerSize", "stickerShape", "hideStickerTime", "hideStickerChecks", "hideStickerReplyColors", "hideStickerReplyEmoji", "hideStickerReplyBackground", "onlyAdded", "recent", "hidePaidReactions":
        return (.stickers, key)
    case "stickerReplies":
        return (.stickers, "hideStickerReplyColors")
    case "reactions":
        return (.stickers, "reactionsInChannels")
    case "profileId", "dialogIdFormat", "dc", "regDate", "chatDate", "mutualContact", "relativeOnlineTime", "hidePhoneNumber", "premiumStatuses", "hideVerification":
        return (.profiles, key)
    case "iconAndIsland", "snow":
        return (.iconAndEffects, key)
    case "glow":
        return (.iconAndEffects, "avatarGlow")
    case "camera", "rememberCamera", "zoomSlider", "staticZoom", "builtInMic", "doubleTapSeek", "autoPause", "autoplayMedia", "transcription":
        return (.media, key)
    case "pauseMusicOnRecording":
        return (.media, "pauseMusicRoundVideos")
    case "autoPauseMedia":
        return (.media, "autoPause")
    case "autoplayMediaTypes":
        return (.media, "autoplayMedia")
    case "downloadAcceleration", "accelerateUpload":
        return (.downloads, key)
    case "confirmCalls", "confirmReactionsInUnjoinedChats", "confirmTelegramLinks", "confirmChatPreviewEntry", "telegramStatistics":
        return (.security, key)
    case "disableAds", "hideGiftButton", "hideBirthdayNotifications", "disableGiftStarsRedirect":
        return (.adsAndGifts, key)
    case "visualPhone", "visualRating", "visualUsernames", "visualId", "visualLabel", "localPremium":
        return (.localProfile, key)
    default:
        return (.root, key)
    }
}

/// A row shown only while the switch above it is on: until then a link to it leads to that switch.
private func dgShownRow(page: DGSettingsPage, key: String) -> String {
    let s = DGSimpleSettings.shared
    switch page {
    case .saving where key == "saveOwnDeleted" && !s.saveDeletedMessages:
        return "saveDeleted"
    case .profiles where key == "dialogIdFormat" && !s.showProfileId:
        return "profileId"
    case .media where ["autoPauseVideo", "autoPauseVoice", "autoPauseRound"].contains(key) && !s.autoPause:
        return "autoPause"
    case .media where ["autoplayVoice", "autoplayRound"].contains(key) && !s.disableMediaAutoplay:
        return "autoplayMedia"
    default:
        return key
    }
}

private func dgPageController(_ page: DGSettingsPage, context: AccountContext, focusKey: String) -> ViewController {
    switch page {
    case .root: return dgSettingsController(context: context, focusKey: focusKey)
    case .ghost: return dgGhostSettingsController(context: context, focusKey: focusKey)
    case .saving: return dgSavingSettingsController(context: context, focusKey: focusKey)
    case .bypass: return dgBypassSettingsController(context: context, focusKey: focusKey)
    case .shadowBan: return dgShadowBanController(context: context, focusKey: focusKey)
    case .mainScreen: return dgMainScreenSettingsController(context: context, focusKey: focusKey)
    case .messages: return dgMessagesSettingsController(context: context, focusKey: focusKey)
    case .stickers: return dgStickersSettingsController(context: context, focusKey: focusKey)
    case .profiles: return dgProfilesSettingsController(context: context, focusKey: focusKey)
    case .iconAndEffects: return dgIconAndEffectsSettingsController(context: context, focusKey: focusKey)
    case .media: return dgMediaSettingsController(context: context, focusKey: focusKey)
    case .downloads: return dgDownloadsSettingsController(context: context, focusKey: focusKey)
    case .security: return dgSecuritySettingsController(context: context, focusKey: focusKey)
    case .adsAndGifts: return dgAdsAndGiftsSettingsController(context: context, focusKey: focusKey)
    case .localProfile: return dgLocalProfileSettingsController(context: context, focusKey: focusKey)
    case .about: return dgAboutController(context: context, focusKey: focusKey)
    case .iconAndIsland: return dgIconAndIslandController(context: context, focusKey: focusKey)
    case .visualId: return dgVisualIdController(context: context, focusKey: focusKey)
    case .visualRating: return dgVisualRatingController(context: context, focusKey: focusKey)
    case .visualUsernames: return dgVisualUsernamesController(context: context, focusKey: focusKey)
    case .visualPhone: return dgVisualPhoneController(context: context, focusKey: focusKey)
    case .visualLabel: return dgVisualLabelController(context: context, focusKey: focusKey)
    case .savedDeleted: return dgSavedDeletedMessagesController(context: context, focusKey: focusKey)
    case .general, .ghostOptions, .silent, .appearance, .dialogId, .chats, .channelBottomButton, .glow, .stickerReplies, .chatListAppearance, .chatListTitle, .doubleTapSeek, .camera, .autoplayMedia, .autoPause, .musicPlaybackExceptions, .transcription, .reactions, .support:
        // dgCurrentRowLocation never leads to a page that is gone.
        return dgSettingsController(context: context, focusKey: focusKey)
    }
}
