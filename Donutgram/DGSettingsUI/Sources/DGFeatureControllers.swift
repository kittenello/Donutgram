import Display
import AccountContext
import DGSimpleSettings
import Postbox
import SwiftSignalKit
import TelegramUIPreferences
import TelegramCore
import SettingsUI

public func dgSpySettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    let accountId = context.account.peerId.toInt64()
    return dgController(context: context, page: .general, title: "Основные", focusKey: focusKey, entries: {
        var result: [DGListEntry] = [.header(0, 0, "РЕЖИМ ПРИЗРАКА"), .disclosure(1, 0, "ghost", "Режим призрака", s.ghostModeEnabled ? "Включен" : "Выключен"), .header(10, 1, "ОСНОВНЫЕ"), .toggle(11, 1, "saveDeleted", "Сохранять удаленки", s.saveDeletedMessages, true)]
        if s.saveDeletedMessages { result.append(.toggle(12, 1, "transparentDeleted", "Полупрозрачные удаленки", s.semiTransparentDeletedMessages, true)) }
        result.append(contentsOf: [.toggle(13, 1, "saveEdits", "Сохранять историю правок", s.saveEditHistory, true), .toggle(14, 1, "saveOnce", "Сохранять одноразки", s.saveViewOnceMedia, true), .toggle(15, 1, "saveBots", "Сохранять в чатах с ботами", s.saveInBotChats, true), .toggle(16, 1, "disappearedGifts", "Видеть удаленные подарки", s.showDisappearedGifts, true), .toggle(17, 1, "saveProtectedStories", "Сохранять запрещенные истории", s.saveProtectedStories, true), .toggle(18, 1, "gifUnlock", "Обход блокировок GIF", s.gifUnlock, true)])
        // Its own append: one more case with a ternary in the literal above risks the compiler's type-check time limit.
        let shadowBanCount = s.shadowBannedPeerIds.count
        result.append(.disclosure(19, 1, "shadowBan", "Теневой бан", shadowBanCount == 0 ? "Выключен" : "\(shadowBanCount)"))
        result.append(contentsOf: [.header(20, 2, "ПЕРЕСЫЛКА"), .toggle(21, 2, "bypassForward", "Запрещенная рассылка", s.bypassForwardRestrictions, true), .header(25, 3, "УСКОРЕНИЕ ЗАГРУЗКИ"), .speedSlider(26, 3, s.downloadAcceleration), .toggle(27, 3, "accelerateUpload", "Ускорение отправки", s.accelerateUpload, true), .info(28, 3, "Ультра использует больше одновременных соединений. На медленном интернете это может мешать загрузке файлов и просмотру видео."), .header(30, 4, "ДРУГОЕ"), .disclosure(31, 4, "visualPhone", "Визуальный номер", s.visualPhoneEnabled ? (s.visualPhoneNumber.isEmpty ? "Включен" : s.visualPhoneNumber) : "Выключен"), .disclosure(32, 4, "visualRating", "Визуальный рейтинг", s.visualRatingLevel(accountId: accountId).map { String($0) } ?? "Выключен"), .disclosure(33, 4, "visualUsernames", "Визуальные NFT-юзернеймы", "\(s.visualUsernames(accountId: accountId).count)"), .disclosure(34, 4, "visualId", "Визуальный ID", s.visualProfileId(accountId: accountId).isEmpty ? "Выключен" : s.visualProfileId(accountId: accountId)), .toggle(35, 4, "localPremium", "Локальный TG Premium", s.localPremium(accountId: accountId), true)])
        if s.localPremium(accountId: accountId) {
            result.append(.info(36, 4, "Premium включён локально для этого аккаунта. Цвета папок и теги чатов настраиваются в разделе «Папки с чатами» и сохраняются только на этом устройстве. Сервер Telegram по-прежнему проверяет подписку для платных возможностей."))
        }
        return result
    }, restartRequiredKeys: ["localPremium"], toggle: { key, value in
        switch key { case "saveDeleted": s.saveDeletedMessages = value; case "transparentDeleted": s.semiTransparentDeletedMessages = value; case "saveEdits": s.saveEditHistory = value; case "saveOnce": s.saveViewOnceMedia = value; case "saveBots": s.saveInBotChats = value; case "saveProtectedStories": s.saveProtectedStories = value; case "gifUnlock": s.gifUnlock = value; case "disappearedGifts": s.showDisappearedGifts = value; case "bypassForward": s.bypassForwardRestrictions = value; case "accelerateUpload": s.accelerateUpload = value; case "localPremium": s.setLocalPremium(value, accountId: accountId); default: break }
    }, select: { key in
        if key.hasPrefix("downloadAcceleration:"), let value = Int(key.split(separator: ":").last ?? "") { s.downloadAcceleration = value }
    }, open: { key in
        switch key {
        case "ghost": return dgGhostSettingsController(context: context)
        case "visualPhone": return dgVisualPhoneController(context: context)
        case "visualRating": return dgVisualRatingController(context: context)
        case "visualUsernames": return dgVisualUsernamesController(context: context)
        case "visualId": return dgVisualIdController(context: context)
        case "shadowBan": return dgShadowBanController(context: context)
        default: return nil
        }
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

private func dgGhostSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .ghost, title: "Режим призрака", focusKey: focusKey, entries: {
        let count = s.ghostModeEnabled ? [s.ghostReadMessages, s.ghostReadStories, s.ghostSendOnline, s.ghostSendTyping, !s.ghostAutomaticOffline].filter { !$0 }.count : 0
        let silent = ["Никогда", "В режиме призрака", "Всегда"][min(max(s.ghostSendWithoutSound, 0), 2)]
        return [.header(0, 0, "РЕЖИМ ПРИЗРАКА"), .toggle(1, 0, "enabled", "Режим призрака", s.ghostModeEnabled, true), .disclosure(2, 0, "options", "Параметры режима призрака", "\(count)/5"), .toggle(3, 0, "readOnAction", "Читать при действиях", s.ghostReadOnAction, s.ghostModeEnabled), .toggle(4, 0, "scheduled", "Использовать отложку", s.ghostUseScheduledMessages, s.ghostModeEnabled), .disclosure(5, 0, "silent", "Отправлять без звука", silent), .toggle(6, 0, "stories", "Предлагать призрака для сторис", s.ghostSuggestForStories, true)]
    }, toggle: { key, value in
        switch key { case "enabled": s.ghostModeEnabled = value; case "readOnAction": s.ghostReadOnAction = value; case "scheduled": s.ghostUseScheduledMessages = value; case "stories": s.ghostSuggestForStories = value; default: break }
    }, open: { key in key == "options" ? dgGhostOptionsController(context: context) : (key == "silent" ? dgSilentModeController(context: context) : nil) })
}

private func dgGhostOptionsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .ghostOptions, title: "Параметры призрака", focusKey: focusKey, entries: {
        // Every option is checked together with the main switch, so without it they stay off and locked.
        let isOn = s.ghostModeEnabled
        var result: [DGListEntry] = [.header(0, 0, "НЕ ОТПРАВЛЯТЬ"), .toggle(1, 0, "messages", "Отметки о прочтении сообщений", isOn && !s.ghostReadMessages, isOn), .toggle(2, 0, "stories", "Отметки о просмотре историй", isOn && !s.ghostReadStories, isOn), .toggle(3, 0, "online", "Статус «онлайн»", isOn && !s.ghostSendOnline, isOn), .toggle(4, 0, "typing", "Статус «печатает»", isOn && !s.ghostSendTyping, isOn), .toggle(5, 0, "offline", "Автоматический «офлайн»", isOn && s.ghostAutomaticOffline, isOn)]
        if !isOn {
            result.append(.info(6, 0, "Параметры действуют только при включённом режиме призрака."))
        }
        return result
    }, toggle: { key, value in
        switch key { case "messages": s.ghostReadMessages = !value; case "stories": s.ghostReadStories = !value; case "online": s.ghostSendOnline = !value; case "typing": s.ghostSendTyping = !value; case "offline": s.ghostAutomaticOffline = value; default: break }
    })
}

private func dgSilentModeController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .silent, title: "Отправлять без звука", focusKey: focusKey, entries: { [.checkbox(0, 0, "0", "Никогда", s.ghostSendWithoutSound == 0), .checkbox(1, 0, "1", "В режиме призрака", s.ghostSendWithoutSound == 1), .checkbox(2, 0, "2", "Всегда", s.ghostSendWithoutSound == 2)] }, select: { s.ghostSendWithoutSound = Int($0) ?? 0 })
}

func dgAppearanceSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .appearance, title: "Оформление", focusKey: focusKey, entries: {
        var entries: [DGListEntry] = [
            .header(0, 0, "ОСНОВНОЕ"),
            .toggle(1, 0, "premiumStatuses", "Скрыть премиум статусы", s.hidePremiumStatuses, true),
            .toggle(2, 0, "customBackgrounds", "Отключить кастомные фоны", s.disableCustomBackgrounds, true),
            .toggle(3, 0, "hideStories", "Скрыть сторис", s.hideStories, true),
            .header(10, 1, "ПРИЛОЖЕНИЕ"), dgIconAndIslandRow(context: context, id: 11, section: 1),
            .header(20, 3, "ВКЛАДКИ"),
            .tabBarPreview(21, 3, s.tabBarLayout),
            .toggle(22, 3, "hideTabBar", "Скрыть панель вкладок", s.hideTabBar, true),
            .toggle(23, 3, "contacts", "Вкладка Контакты", s.showContactsTab, !s.hideTabBar),
            .toggle(24, 3, "calls", "Вкладка Звонки", s.showCallsTab, !s.hideTabBar),
            .toggle(25, 3, "wideTabBar", "Широкая Панель", s.wideTabBar, !s.hideTabBar),
            .toggle(26, 3, "integratedTabSearch", "Поиск внутри панели", s.integratedTabSearch, !s.hideTabBar),
            .toggle(27, 3, "tabSearchOnLeft", "Поиск слева", s.tabSearchOnLeft, !s.hideTabBar),
            .header(30, 4, "ПРОФИЛЬ"),
            .toggle(31, 4, "profileId", "ID Профилей", s.showProfileId, true)
        ]
        if s.showProfileId {
            entries.append(.disclosure(37, 4, "dialogIdFormat", "Показывать ID диалога", s.dialogIdFormat == .botApi ? "Bot API" : "Telegram API"))
        }
        entries.append(contentsOf: [
            .toggle(32, 4, "dc", "Показывать дата-центр (DC)", s.showDc, true),
            .toggle(33, 4, "regDate", "Показывать дату регистрации", s.showRegistrationDate, true),
            .toggle(34, 4, "chatDate", "Показывать дату создания чата", s.showChatCreationDate, true),
            .toggle(35, 4, "mutualContact", "Показывать взаимный контакт", s.showMutualContact, true),
            .toggle(38, 4, "relativeOnlineTime", "Относительное время онлайна", s.relativeOnlineTime, true),
            .toggle(39, 4, "hidePhoneNumber", "Скрыть номер телефона", s.hidePhoneNumber, true),
            .header(40, 5, "ДРУГОЕ"),
            .toggle(41, 5, "disableAds", "Отключить рекламу", s.disableAds, true),
            .toggle(42, 5, "confirmCalls", "Подтверждение вызова", s.confirmCalls, true)
        ])
        return entries
    }, restartRequiredKeys: ["premiumStatuses", "hideStories", "hideTabBar"], toggle: { key, value in
        switch key { case "premiumStatuses": s.hidePremiumStatuses = value; case "customBackgrounds": s.disableCustomBackgrounds = value; case "hideStories": s.hideStories = value; case "snow": s.forceSnow = value; case "hideTabBar": s.hideTabBar = value; case "contacts": s.showContactsTab = value; case "calls": s.showCallsTab = value; case "wideTabBar": s.wideTabBar = value; case "integratedTabSearch": s.integratedTabSearch = value; case "tabSearchOnLeft": s.tabSearchOnLeft = value; case "profileId": s.showProfileId = value; case "dc": s.showDc = value; case "regDate": s.showRegistrationDate = value; case "chatDate": s.showChatCreationDate = value; case "mutualContact": s.showMutualContact = value; case "relativeOnlineTime": s.relativeOnlineTime = value; case "hidePhoneNumber": s.hidePhoneNumber = value; case "confirmCalls": s.confirmCalls = value; case "disableAds": s.disableAds = value; default: break }
    }, open: { key in
        switch key {
        case "dialogIdFormat": return dgDialogIdFormatController(context: context)
        case "iconAndIsland": return dgIconAndIslandController(context: context)
        default: return nil
        }
    })
}

/// The row on «Оформление» that opens «Иконка и остров», the same row as in the stock appearance settings.
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
                .info(2, 0, "Остров прячется под вырезом камеры — его видно только на скриншотах и записи экрана."),
                .toggle(10, 1, "islandFollowsIcon", "Остров как у иконки", s.islandFollowsIcon, true)
            ])
            if s.islandFollowsIcon {
                entries.append(.info(12, 1, "Выбираешь иконку — остров меняется на такой же."))
            } else {
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

private func dgDialogIdFormatController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .dialogId, title: "ID диалога", focusKey: focusKey, entries: {
        [.checkbox(0, 0, "0", "Telegram API", s.dialogIdFormat == .telegramApi),
         .checkbox(1, 0, "1", "Bot API", s.dialogIdFormat == .botApi)]
    }, select: { s.dialogIdFormat = $0 == "1" ? .botApi : .telegramApi })
}

func dgChatsSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    var previewSticker: TelegramMediaFile?
    let stickerSource: Signal<TelegramMediaFile?, NoError> = context.account.postbox.transaction { transaction -> TelegramMediaFile? in
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
    let previewUpdates = (Signal<TelegramMediaFile?, NoError>.single(nil) |> then(stickerSource))
    |> deliverOnMainQueue
    |> map { file -> Void in previewSticker = file }
    return dgController(context: context, page: .chats, title: "Внешний вид", focusKey: focusKey, entries: {
        let hiddenCount = [1, 2, 4].filter { s.hiddenReactions & $0 != 0 }.count
        let transcription = dgTranscriptionBackendTitle(s.transcriptionBackend)
        let cameraTitle: String
        switch s.roundVideoCamera {
        case .front: cameraTitle = "Фронтальная"
        case .rear: cameraTitle = "Основная"
        case .ask: cameraTitle = "Спрашивать"
        }
        let musicOptions: [DGSimpleSettings.MusicPlaybackExceptions] = [.roundVideos, .voiceRecording, .voicePlayback]
        var result: [DGListEntry] = [
            .header(-30, 0, "СТИКЕРЫ"),
            .stickerSizeSlider(-29, 0, s.stickerSize),
            .stickerPreview(-28, 0, s.stickerSize, s.hideStickerTime, s.hideStickerChecks, s.stickerReplyOptions, s.stickerShape, previewSticker),
            .toggle(-27, 0, "hideStickerTime", "Скрыть время на стикерах", s.hideStickerTime, true),
            .toggle(-26, 0, "hideStickerChecks", "Скрыть галочки на стикерах", s.hideStickerChecks, true),
            .stickerReplies(-25, 0, s.stickerReplyOptions)
        ]
        result.append(contentsOf: [
            .header(-23, 1, "ФОРМА СТИКЕРОВ"),
            .stickerShape(-22, 1, s.stickerShape),
            .header(0, 2, "СТИКЕРЫ И ЭМОДЗИ"),
            .toggle(1, 2, "onlyAdded", "Показывать только добавленные стикеры", s.onlyAddedStickers, true),
            .toggle(2, 2, "recent", "Беск. недавние стикеры", s.infiniteRecentStickers, true),
            .disclosure(3, 2, "reactions", "Скрыть реакции", "\(hiddenCount)/3"),
            .header(4, 3, "ВНЕШНИЙ ВИД"),
            .disclosure(5, 3, "chatListAppearance", "Внешний вид", ""),
            .header(10, 4, "СООБЩЕНИЯ"),
            .messagePreview(11, 4, s.removeMessageTails, s.showMessageSeconds, s.disableColoredReplies, s.editedIcon),
            .toggle(12, 4, "tails", "Убрать хвост у сообщений", s.removeMessageTails, true),
            .toggle(13, 4, "seconds", "Показывать секунды", s.showMessageSeconds, true),
            .toggle(14, 4, "replies", "Отключить цветные ответы", s.disableColoredReplies, true),
            .toggle(15, 4, "editedIcon", "Заменять «изменено» иконкой", s.editedIcon, true),
            .toggle(16, 4, "onlineIndicator", "Показывать индикатор онлайна", s.showOnlineIndicator, true),
            .toggle(17, 4, "greetingSticker", "Скрыть приветственный стикер", s.hideGreetingSticker, true),
            .toggle(18, 4, "mentionComma", "Запятая после упоминания", s.commaAfterMention, true),
            .toggle(19, 4, "mentionAvatars", "Аватарки в упоминаниях", s.mentionAvatars, true),
            .toggle(20, 4, "pollResultsBeforeVoting", "Итоги до голосования", s.showPollResultsBeforeVoting, true),
            .toggle(21, 4, "channelForwardCount", "Счетчик пересылок в каналах", s.showChannelForwardCount, true),
            .toggle(22, 4, "forwardDate", "Время пересылки", s.showForwardDate, true),
            .header(24, 5, "ГОЛОС В ТЕКСТ"),
            .disclosure(25, 5, "transcription", "Сервис", transcription),
            .header(30, 6, "ЗАПИСЬ"),
            .disclosure(31, 6, "camera", "Камера в кружках", cameraTitle),
            .toggle(32, 6, "rememberCamera", "Запоминать последнюю камеру", s.rememberRoundVideoCamera, true),
            .toggle(33, 6, "zoomSlider", "Слайдер зума", s.roundVideoZoomSlider, true),
            .toggle(34, 6, "staticZoom", "Оставлять зум после щипка", s.staticRoundVideoZoom, true),
            .disclosure(35, 6, "pauseMusicOnRecording", "Пауза музыки при записи", "\(musicOptions.filter { s.musicPlaybackExceptions.contains($0) }.count)/3"),
            .toggle(36, 6, "builtInMic", "Встроенный микрофон", s.forceBuiltInMicrophone, true),
            .header(40, 7, "ВИДЕО"),
            .disclosure(41, 7, "doubleTapSeek", "Перемотка двойным нажатием", s.doubleTapSeekSeconds == 0 ? "Отключено" : "\(s.doubleTapSeekSeconds) сек."),
            .toggle(42, 7, "autoPause", "Авто пауза", s.autoPause, true),
            .disclosure(43, 7, "autoPauseMedia", "Приостанавливать", "\([1, 2, 4].filter { s.autoPauseMedia & $0 != 0 }.count)/3"),
            .header(50, 8, "ДРУГОЕ"),
            .toggle(51, 8, "hideArchive", "Скрывать архив из списка чатов", s.hideArchive, true)
        ])
        if s.hideArchive {
            result.append(.toggle(52, 8, "openArchiveOnPull", "Открывать архив при вытягивании", s.openArchiveOnPull, true))
        }
        result.append(contentsOf: [
            .header(60, 9, "КАНАЛЫ"),
            .toggle(61, 9, "wideChannelPosts", "Широкие посты в каналах", s.wideChannelPosts, true),
            .disclosure(62, 9, "channelBottomButton", "Нижняя кнопка", dgChannelBottomButtonTitle(s.channelBottomButton)),
            .header(70, 10, "ЭФФЕКТЫ"), .disclosure(71, 10, "glow", "Свечение", "\([s.avatarGlow, s.reactionGlow].filter { $0 }.count)/2")
        ])
        return result
    }, additionalUpdates: previewUpdates, toggle: { key, value in
        switch key {
        case "onlyAdded": s.onlyAddedStickers = value
        case "recent": s.infiniteRecentStickers = value
        case "hideStickerTime": s.hideStickerTime = value
        case "hideStickerChecks": s.hideStickerChecks = value
        case "stickerReplies": s.stickerReplyOptions = value ? 7 : 0
        case "tails": s.removeMessageTails = value
        case "seconds": s.showMessageSeconds = value
        case "replies": s.disableColoredReplies = value
        case "editedIcon": s.editedIcon = value
        case "onlineIndicator": s.showOnlineIndicator = value
        case "greetingSticker": s.hideGreetingSticker = value
        case "mentionComma": s.commaAfterMention = value
        case "mentionAvatars": s.mentionAvatars = value
        case "pollResultsBeforeVoting": s.showPollResultsBeforeVoting = value
        case "channelForwardCount": s.showChannelForwardCount = value
        case "forwardDate": s.showForwardDate = value
        case "wideChannelPosts": s.wideChannelPosts = value
        case "rememberCamera": s.rememberRoundVideoCamera = value
        case "zoomSlider": s.roundVideoZoomSlider = value
        case "staticZoom": s.staticRoundVideoZoom = value
        case "builtInMic": s.forceBuiltInMicrophone = value
        case "autoPause": s.autoPause = value
        case "hideArchive":
            s.hideArchive = value
            let _ = updateChatArchiveSettings(engine: context.engine, { current in
                var current = current
                current.isHiddenByDefault = value
                return current
            }).startStandalone()
        case "openArchiveOnPull": s.openArchiveOnPull = value
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
    }, open: { key in
        switch key {
        case "reactions": return dgHiddenReactionsController(context: context)
        case "channelBottomButton": return dgChannelBottomButtonController(context: context)
        case "stickerReplyOptions": return dgStickerRepliesController(context: context)
        case "glow": return dgGlowController(context: context)
        case "transcription": return dgTranscriptionController(context: context)
        case "camera": return dgRoundVideoCameraController(context: context)
        case "autoPauseMedia": return dgAutoPauseMediaController(context: context)
        case "doubleTapSeek": return dgDoubleTapSeekController(context: context)
        case "chatListAppearance": return dgChatListAppearanceController(context: context)
        case "pauseMusicOnRecording": return dgMusicPlaybackExceptionsController(context: context)
        default: return nil
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

private func dgChannelBottomButtonController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let settings = DGSimpleSettings.shared
    return dgController(context: context, page: .channelBottomButton, title: "Нижняя кнопка", focusKey: focusKey, entries: {
        DGSimpleSettings.ChannelBottomButton.allCases.enumerated().map { index, value in
            .checkbox(Int32(index), 0, String(value.rawValue), dgChannelBottomButtonTitle(value), settings.channelBottomButton == value)
        } + [.info(3, 0, "«Обсудить» открывает группу обсуждения канала. В каналах без обсуждения кнопка скрыта.")]
    }, select: { key in
        settings.channelBottomButton = DGSimpleSettings.ChannelBottomButton(rawValue: Int(key) ?? 1) ?? .mute
    })
}

private func dgGlowController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let settings = DGSimpleSettings.shared
    return dgController(context: context, page: .glow, title: "Свечение", focusKey: focusKey, entries: {
        [.toggle(0, 0, "avatarGlow", "Свечение аватарок", settings.avatarGlow, true),
         .toggle(1, 0, "reactionGlow", "Свечение реакций", settings.reactionGlow, true)]
    }, toggle: { key, value in
        if key == "avatarGlow" { settings.avatarGlow = value }
        else if key == "reactionGlow" { settings.reactionGlow = value }
    })
}

private func dgStickerRepliesController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let settings = DGSimpleSettings.shared
    return dgController(context: context, page: .stickerReplies, title: "Ответы на стикеры", focusKey: focusKey, entries: {
        [.checkbox(0, 0, "1", "Цвета", settings.stickerReplyOptions & 1 != 0),
         .checkbox(1, 0, "2", "Эмодзи", settings.stickerReplyOptions & 2 != 0),
         .checkbox(2, 0, "4", "Фон", settings.stickerReplyOptions & 4 != 0)]
    }, select: { key in
        if let option = Int(key), [1, 2, 4].contains(option) { settings.stickerReplyOptions ^= option }
    })
}

private func dgChatListAppearanceController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let settings = DGSimpleSettings.shared
    return dgController(context: context, page: .chatListAppearance, title: "Внешний вид", focusKey: focusKey, entries: {
        [
            .header(0, 0, "СПИСОК ЧАТОВ"),
            .chatListPreview(1, 0, settings.forceSnow, settings.chatListHideEmojiStatus, settings.chatListCenteredTitle, settings.chatListHideSearch, settings.chatListTitleMode.rawValue),
            .toggle(2, 0, "snow", "Снег", settings.forceSnow, true),
            .toggle(3, 0, "hideStatus", "Скрыть статус соединения", settings.chatListHideStatus, true),
            .toggle(4, 0, "hideEmojiStatus", "Скрыть эмодзи-статус", settings.chatListHideEmojiStatus, true),
            .toggle(5, 0, "centerTitle", "Заголовок по центру", settings.chatListCenteredTitle, true),
            .toggle(6, 0, "hideSearch", "Скрыть строку поиска", settings.chatListHideSearch, true),
            .disclosure(7, 0, "titleMode", "Текст в заголовке", dgChatListTitleModeTitle(settings.chatListTitleMode)),
            .toggle(8, 0, "foldersAtBottom", "Папки внизу", settings.chatListFoldersAtBottom, true)
        ]
    }, toggle: { key, value in
        switch key {
        case "snow": settings.forceSnow = value
        case "hideStatus": settings.chatListHideStatus = value
        case "hideEmojiStatus": settings.chatListHideEmojiStatus = value
        case "centerTitle": settings.chatListCenteredTitle = value
        case "hideSearch": settings.chatListHideSearch = value
        case "foldersAtBottom": settings.chatListFoldersAtBottom = value
        default: break
        }
    }, open: { key in
        key == "titleMode" ? dgChatListTitleModeController(context: context) : nil
    })
}

private func dgMusicPlaybackExceptionsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    let options: [(String, DGSimpleSettings.MusicPlaybackExceptions)] = [
        ("Кружки", .roundVideos),
        ("Голосовые сообщения", .voiceRecording),
        ("Прослушивание голосовые сообщения", .voicePlayback)
    ]
    return dgController(context: context, page: .musicPlaybackExceptions, title: "Пауза музыки при записи", focusKey: focusKey, entries: {
        options.enumerated().map { index, option in
            .checkbox(Int32(index), 0, String(option.1.rawValue), option.0, s.musicPlaybackExceptions.contains(option.1))
        }
    }, select: { key in
        guard let option = options.first(where: { String($0.1.rawValue) == key })?.1 else { return }
        s.musicPlaybackExceptions.formSymmetricDifference(option)
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

private func dgChatListTitleModeController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let settings = DGSimpleSettings.shared
    let modes: [DGSimpleSettings.ChatListTitleMode] = [.donutgram, .username, .nickname, .chats]
    return dgController(context: context, page: .chatListTitle, title: "Текст в заголовке", focusKey: focusKey, entries: {
        modes.enumerated().map { index, mode in
            .checkbox(Int32(index), 0, String(mode.rawValue), dgChatListTitleModeTitle(mode), settings.chatListTitleMode == mode)
        }
    }, select: { key in
        settings.chatListTitleMode = DGSimpleSettings.ChatListTitleMode(rawValue: Int(key) ?? 0) ?? .chats
    })
}

private func dgDoubleTapSeekController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let settings = DGSimpleSettings.shared
    let values = [0, 5, 10, 15, 30]
    return dgController(context: context, page: .doubleTapSeek, title: "Перемотка двойным нажатием", focusKey: focusKey, entries: {
        values.enumerated().map { index, value in
            .checkbox(Int32(index), 0, String(value), value == 0 ? "Отключено" : "\(value) секунд", settings.doubleTapSeekSeconds == value)
        }
    }, select: { settings.doubleTapSeekSeconds = Int($0) ?? 15 })
}

private func dgRoundVideoCameraController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .camera, title: "Камера в кружках", focusKey: focusKey, entries: {
        [.checkbox(0, 0, "0", "Фронтальная", s.roundVideoCamera == .front),
         .checkbox(1, 0, "1", "Основная", s.roundVideoCamera == .rear),
         .checkbox(2, 0, "2", "Спрашивать", s.roundVideoCamera == .ask)]
    }, select: { s.roundVideoCamera = DGSimpleSettings.RoundVideoCamera(rawValue: Int($0) ?? 0) ?? .front })
}

private func dgAutoPauseMediaController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .autoPause, title: "Авто пауза", focusKey: focusKey, entries: {
        [.toggle(0, 0, "1", "Видео", s.autoPauseMedia & 1 != 0, true),
         .toggle(1, 0, "2", "Голосовых", s.autoPauseMedia & 2 != 0, true),
         .toggle(2, 0, "4", "Кружков", s.autoPauseMedia & 4 != 0, true)]
    }, toggle: { key, value in
        let bit = Int(key) ?? 0
        s.autoPauseMedia = value ? (s.autoPauseMedia | bit) : (s.autoPauseMedia & ~bit)
    })
}

func dgDownloadsSettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let settings = DGSimpleSettings.shared
    return dgController(context: context, page: .downloads, title: "Скачивание", focusKey: focusKey, entries: {
        [.header(0, 0, "СКАЧИВАНИЕ"), .toggle(1, 0, "downloadTikTok", "Скачивать TikTok", settings.downloadTikTok, true), .toggle(2, 0, "downloadShorts", "Скачивать YT Shorts", settings.downloadYouTubeShorts, true), .toggle(3, 0, "signDownloads", "Подписывать", settings.signDownloadedMedia, true)]
    }, toggle: { key, value in
        switch key { case "downloadTikTok": settings.downloadTikTok = value; case "downloadShorts": settings.downloadYouTubeShorts = value; case "signDownloads": settings.signDownloadedMedia = value; default: break }
    })
}

private func dgTranscriptionBackendTitle(_ backend: DGSimpleSettings.TranscriptionBackend) -> String {
    switch backend {
    case .auto: return "Авто"
    case .telegram: return "Telegram"
    case .apple: return "Apple"
    }
}

private func dgTranscriptionController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .transcription, title: "Голос в текст", focusKey: focusKey, entries: {
        let backend = s.transcriptionBackend
        let info: String
        switch backend {
        case .auto: info = "Telegram, пока он может расшифровать сообщение сам — с Premium или бесплатными попытками. Иначе Apple."
        case .telegram: info = "Telegram использует облачный сервис распознавания."
        case .apple: info = "Apple распознаёт речь на устройстве, а если язык не поддерживается — на серверах Apple."
        }
        return [.checkbox(0, 0, "auto", "Авто", backend == .auto), .checkbox(1, 0, "telegram", "Telegram", backend == .telegram), .checkbox(2, 0, "apple", "Apple", backend == .apple), .info(3, 0, info)]
    }, select: { s.transcriptionBackend = DGSimpleSettings.TranscriptionBackend(rawValue: $0) ?? .auto })
}

private func dgHiddenReactionsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .reactions, title: "Скрыть реакции", focusKey: focusKey, entries: { [.toggle(0, 0, "1", "Каналы", s.hiddenReactions & 1 != 0, true), .toggle(1, 0, "2", "Группы", s.hiddenReactions & 2 != 0, true), .toggle(2, 0, "4", "Личные чаты", s.hiddenReactions & 4 != 0, true)] }, toggle: { key, value in
        let mask = Int(key) ?? 0
        s.hiddenReactions = value ? (s.hiddenReactions | mask) : (s.hiddenReactions & ~mask)
    })
}

func dgSupportController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    dgController(context: context, page: .support, title: "Поддержка", focusKey: focusKey, entries: { [.header(0, 0, "ПОДДЕРЖКА"), .info(1, 0, "Раздел подготовлен для ссылок на поддержку и информацию о Donutgram.")] })
}

public func dgSettingsControllerForLink(context: AccountContext, page: String, key: String) -> ViewController? {
    guard let page = DGSettingsPage(rawValue: page) else {
        return nil
    }
    let focusKey: String
    if page == .chats && key == "openArchiveOnPull" && !DGSimpleSettings.shared.hideArchive {
        focusKey = "hideArchive"
    } else if page == .appearance && key == "dialogIdFormat" && !DGSimpleSettings.shared.showProfileId {
        focusKey = "profileId"
    } else if page == .general && key == "transparentDeleted" && !DGSimpleSettings.shared.saveDeletedMessages {
        focusKey = "saveDeleted"
    } else {
        focusKey = key
    }
    let makeController: (AccountContext, String?) -> ViewController
    switch page {
    case .root: makeController = dgSettingsController
    case .general: makeController = dgSpySettingsController
    case .ghost: makeController = dgGhostSettingsController
    case .ghostOptions: makeController = dgGhostOptionsController
    case .silent: makeController = dgSilentModeController
    case .appearance: makeController = dgAppearanceSettingsController
    case .iconAndIsland: makeController = dgIconAndIslandController
    case .dialogId: makeController = dgDialogIdFormatController
    case .chats: makeController = dgChatsSettingsController
    case .channelBottomButton: makeController = dgChannelBottomButtonController
    case .chatListAppearance: makeController = dgChatListAppearanceController
    case .chatListTitle: makeController = dgChatListTitleModeController
    case .doubleTapSeek: makeController = dgDoubleTapSeekController
    case .camera: makeController = dgRoundVideoCameraController
    case .autoPause: makeController = dgAutoPauseMediaController
    case .musicPlaybackExceptions: makeController = dgMusicPlaybackExceptionsController
    case .downloads: makeController = dgDownloadsSettingsController
    case .transcription: makeController = dgTranscriptionController
    case .reactions: makeController = dgHiddenReactionsController
    case .stickerReplies: makeController = dgStickerRepliesController
    case .glow: makeController = dgGlowController
    case .visualId: makeController = dgVisualIdController
    case .visualRating: makeController = dgVisualRatingController
    case .visualUsernames: makeController = dgVisualUsernamesController
    case .visualPhone: makeController = dgVisualPhoneController
    case .shadowBan: makeController = dgShadowBanController
    case .support: makeController = dgSupportController
    }
    return makeController(context, focusKey)
}
