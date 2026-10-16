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

public func dgSpySettingsController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    let accountId = context.account.peerId.toInt64()
    return dgController(context: context, page: .general, title: "Основные", focusKey: focusKey, entries: {
        var result: [DGListEntry] = [.header(0, 0, "РЕЖИМ ПРИЗРАКА"), .disclosure(1, 0, "ghost", "Режим призрака", s.ghostModeEnabled ? "Включен" : "Выключен"), .header(10, 1, "ОСНОВНЫЕ"), .toggle(11, 1, "saveDeleted", "Сохранять удаленки", s.saveDeletedMessages, true)]
        if s.saveDeletedMessages { result.append(.toggle(12, 1, "saveOwnDeleted", "Сохранять свои удаленки", s.saveOwnDeletedMessages, true)) }
        // Shown with saving off as well: what was saved before stays, and keeps its look, until it is deleted here.
        result.append(contentsOf: [.toggle(13, 1, "transparentDeleted", "Полупрозрачные удаленки", s.semiTransparentDeletedMessages, true), .disclosure(14, 1, "savedDeleted", "Сохраненные удаленки", "")])
        result.append(contentsOf: [.toggle(15, 1, "saveEdits", "Сохранять историю правок", s.saveEditHistory, true), .toggle(16, 1, "saveOnce", "Сохранять одноразки", s.saveViewOnceMedia, true), .toggle(17, 1, "saveBots", "Сохранять в чатах с ботами", s.saveInBotChats, true), .toggle(18, 1, "disappearedGifts", "Видеть удаленные подарки", s.showDisappearedGifts, true), .toggle(19, 1, "saveProtectedStories", "Сохранять запрещенные истории", s.saveProtectedStories, true), .toggle(20, 1, "gifUnlock", "Обход блокировок GIF", s.gifUnlock, true)])
        // Its own append: one more case with a ternary in the literal above risks the compiler's type-check time limit.
        let shadowBanCount = s.shadowBannedPeerIds.count
        result.append(.disclosure(21, 1, "shadowBan", "Теневой бан", shadowBanCount == 0 ? "Выключен" : "\(shadowBanCount)"))
        result.append(contentsOf: [.header(22, 2, "ПЕРЕСЫЛКА"), .toggle(23, 2, "bypassForward", "Запрещенная рассылка", s.bypassForwardRestrictions, true)])
        result.append(contentsOf: [.toggle(24, 2, "protectedScreenshots", "Скриншоты в защищённых чатах", s.allowProtectedScreenshots, true)])
        result.append(contentsOf: [.header(26, 3, "УСКОРЕНИЕ ЗАГРУЗКИ"), .speedSlider(27, 3, s.downloadAcceleration), .toggle(28, 3, "accelerateUpload", "Ускорение отправки", s.accelerateUpload, true), .info(29, 3, "Ультра использует больше одновременных соединений. На медленном интернете это может мешать загрузке файлов и просмотру видео."), .header(30, 4, "ДРУГОЕ"), .disclosure(31, 4, "visualPhone", "Визуальный номер", s.visualPhoneEnabled ? (s.visualPhoneNumber.isEmpty ? "Включен" : s.visualPhoneNumber) : "Выключен"), .disclosure(32, 4, "visualRating", "Визуальный рейтинг", s.visualRatingLevel(accountId: accountId).map { String($0) } ?? "Выключен"), .disclosure(33, 4, "visualUsernames", "Визуальные NFT-юзернеймы", "\(s.visualUsernames(accountId: accountId).count)"), .disclosure(34, 4, "visualId", "Визуальный ID", s.visualProfileId(accountId: accountId).isEmpty ? "Выключен" : s.visualProfileId(accountId: accountId)), .toggle(35, 4, "localPremium", "Локальный TG Premium", s.localPremium(accountId: accountId), true)])
        if s.localPremium(accountId: accountId) {
            result.append(.info(36, 4, "Premium включён локально для этого аккаунта. Цвета папок и теги чатов настраиваются в разделе «Папки с чатами» и сохраняются только на этом устройстве. Сервер Telegram по-прежнему проверяет подписку для платных возможностей."))
        }
        result.append(contentsOf: [.header(40, 5, "СТАТИСТИКА"), .toggle(41, 5, "telegramStatistics", "Отправлять статистику в Telegram", s.sendTelegramStatistics, true), .info(42, 5, "Аналитика приложения, время чтения постов в каналах, прослушанная музыка, служебные логи и данные о качестве звонков, как в обычном Telegram. Сетевая телеметрия не отправляется никогда.")])
        return result
    }, restartRequiredKeys: ["localPremium"], toggle: { key, value in
        switch key { case "telegramStatistics": s.sendTelegramStatistics = value; case "saveDeleted": s.saveDeletedMessages = value; case "saveOwnDeleted": s.saveOwnDeletedMessages = value; case "transparentDeleted": s.semiTransparentDeletedMessages = value; case "saveEdits": s.saveEditHistory = value; case "saveOnce": s.saveViewOnceMedia = value; case "saveBots": s.saveInBotChats = value; case "saveProtectedStories": s.saveProtectedStories = value; case "gifUnlock": s.gifUnlock = value; case "disappearedGifts": s.showDisappearedGifts = value; case "bypassForward": s.bypassForwardRestrictions = value; case "protectedScreenshots": s.allowProtectedScreenshots = value; case "accelerateUpload": s.accelerateUpload = value; case "localPremium": s.setLocalPremium(value, accountId: accountId); default: break }
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
        case "savedDeleted": return dgSavedDeletedMessagesController(context: context)
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
        return [.header(0, 0, "РЕЖИМ ПРИЗРАКА"), .toggle(1, 0, "enabled", "Режим призрака", s.ghostModeEnabled, true), .disclosure(2, 0, "options", "Параметры режима призрака", "\(count)/5"), .toggle(3, 0, "readOnAction", "Читать при действиях", s.ghostReadOnAction, s.ghostModeEnabled), .toggle(4, 0, "scheduled", "Использовать отложку", s.ghostUseScheduledMessages, s.ghostModeEnabled), .disclosure(5, 0, "silent", "Отправлять без звука", silent), .toggle(6, 0, "stories", "Предлагать призрака для сторис", s.ghostSuggestForStories, true), .header(10, 1, "ЧТЕНИЕ"), .disclosure(11, 1, "readAll", "Прочитать все на сервере", ""), .disclosure(12, 1, "readAllLocal", "Прочитать все локально", "")]
    }, toggle: { key, value in
        switch key { case "enabled": s.ghostModeEnabled = value; case "readOnAction": s.ghostReadOnAction = value; case "scheduled": s.ghostUseScheduledMessages = value; case "stories": s.ghostSuggestForStories = value; default: break }
    }, open: { key in key == "options" ? dgGhostOptionsController(context: context) : (key == "silent" ? dgSilentModeController(context: context) : nil) }, perform: { key, controller in
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
            .toggle(2, 0, "hideVerification", "Скрыть верификацию", s.hideVerification, true),
            .toggle(3, 0, "customBackgrounds", "Отключить кастомные фоны", s.disableCustomBackgrounds, true),
            .toggle(4, 0, "hideStories", "Скрыть сторис", s.hideStories, true),
            .toggle(5, 0, "hideBirthdayNotifications", "Скрыть уведомление о дне рождении", s.hideBirthdayNotifications, true),
            .header(10, 1, "ПРИЛОЖЕНИЕ"), dgIconAndIslandRow(context: context, id: 11, section: 1),
            .header(20, 3, "ВКЛАДКИ"),
            .tabBarPreview(21, 3, s.tabBarLayout),
            .toggle(22, 3, "hideTabBar", "Скрыть панель вкладок", s.hideTabBar, true),
            .toggle(23, 3, "contacts", "Вкладка Контакты", s.showContactsTab, true),
            .toggle(24, 3, "calls", "Вкладка Звонки", s.showCallsTab, true),
            .toggle(25, 3, "wideTabBar", "Широкая Панель", s.wideTabBar, true),
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
    }, restartRequiredKeys: ["premiumStatuses", "hideVerification", "hideStories"], toggle: { key, value in
        switch key { case "hideBirthdayNotifications": s.hideBirthdayNotifications = value; case "premiumStatuses": s.hidePremiumStatuses = value; case "hideVerification": s.hideVerification = value; case "customBackgrounds": s.disableCustomBackgrounds = value; case "hideStories": s.hideStories = value; case "snow": s.forceSnow = value; case "hideTabBar": s.hideTabBar = value; case "contacts": s.showContactsTab = value; case "calls": s.showCallsTab = value; case "wideTabBar": s.wideTabBar = value; case "profileId": s.showProfileId = value; case "dc": s.showDc = value; case "regDate": s.showRegistrationDate = value; case "chatDate": s.showChatCreationDate = value; case "mutualContact": s.showMutualContact = value; case "relativeOnlineTime": s.relativeOnlineTime = value; case "hidePhoneNumber": s.hidePhoneNumber = value; case "confirmCalls": s.confirmCalls = value; case "disableAds": s.disableAds = value; default: break }
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
    var previewEmoji: TelegramMediaFile?
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
    let emojiSource = context.engine.stickers.loadedStickerPack(reference: .iconStatusEmoji, forceActualized: false)
    |> map { result -> TelegramMediaFile? in
        if case let .result(_, items, _) = result { return items.first?.file._parse() }
        return nil
    }
    let previewUpdates = combineLatest(
        Signal<TelegramMediaFile?, NoError>.single(nil) |> then(stickerSource),
        Signal<TelegramMediaFile?, NoError>.single(nil) |> then(emojiSource)
    )
    |> deliverOnMainQueue
    |> map { sticker, emoji -> Void in
        previewSticker = sticker
        previewEmoji = emoji
    }
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
            .stickerPreview(-28, 0, s.stickerSize, s.hideStickerTime, s.hideStickerChecks, s.stickerReplyOptions, s.stickerShape, s.messagePreviewConfiguration, previewSticker, previewEmoji),
            .toggle(-27, 0, "hideStickerTime", "Скрыть время на стикерах", s.hideStickerTime, true),
            .toggle(-26, 0, "hideStickerChecks", "Скрыть галочки на стикерах", s.hideStickerChecks, true),
            .toggle(-25, 0, "hideStickerReplyColors", "Скрыть цвета", s.hideStickerReplyColors, true),
            .toggle(-24, 0, "hideStickerReplyEmoji", "Скрыть эмодзи", s.hideStickerReplyEmoji, true),
            .toggle(-23, 0, "hideStickerReplyBackground", "Скрыть фон", s.hideStickerReplyBackground, true)
        ]
        result.append(contentsOf: [
            .header(-22, 1, "ФОРМА СТИКЕРОВ"),
            .stickerShape(-21, 1, s.stickerShape),
            .header(0, 2, "СТИКЕРЫ И ЭМОДЗИ"),
            .toggle(1, 2, "onlyAdded", "Показывать только добавленные стикеры", s.onlyAddedStickers, true),
            .toggle(2, 2, "recent", "Беск. недавние стикеры", s.infiniteRecentStickers, true),
            .disclosure(3, 2, "reactions", "Скрыть реакции", "\(hiddenCount)/3"),
            .toggle(6, 2, "hidePaidReactions", "Скрыть платные реакции", s.hidePaidReactions, true),
            .header(7, 3, "ВНЕШНИЙ ВИД"),
            .chatListPreview(8, 3, s.forceSnow, s.chatListHideEmojiStatus, s.chatListCenteredTitle, s.chatListHideSearch, s.chatListTitleMode.rawValue),
            .toggle(9, 3, "snow", "Снег", s.forceSnow, true),
            .toggle(10, 3, "hideStatus", "Скрыть статус соединения", s.chatListHideStatus, true),
            .toggle(11, 3, "hideEmojiStatus", "Скрыть эмодзи-статус", s.chatListHideEmojiStatus, true),
            .toggle(12, 3, "centerTitle", "Заголовок по центру", s.chatListCenteredTitle, true),
            .toggle(13, 3, "hideSearch", "Скрыть строку поиска", s.chatListHideSearch, true),
            .disclosure(14, 3, "titleMode", "Текст в заголовке", dgChatListTitleModeTitle(s.chatListTitleMode)),
            .toggle(15, 3, "foldersAtBottom", "Папки внизу", s.chatListFoldersAtBottom, true),
            .header(18, 4, "СООБЩЕНИЯ"),
            .messagePreview(19, 4, s.messagePreviewConfiguration, previewEmoji),
            .toggle(20, 4, "tails", "Убрать хвост у сообщений", s.removeMessageTails, true),
            .toggle(21, 4, "seconds", "Показывать секунды", s.showMessageSeconds, true),
            .toggle(22, 4, "replies", "Отключить цветные ответы", s.disableColoredReplies, true),
            .toggle(23, 4, "hidePremiumReplyEmoji", "Скрыть премиум эмодзи", s.hidePremiumReplyEmoji, true),
            .toggle(24, 4, "editedIcon", "Заменять «изменено» иконкой", s.editedIcon, true),
            .toggle(25, 4, "onlineIndicator", "Показывать индикатор онлайна", s.showOnlineIndicator, true),
            .toggle(26, 4, "greetingSticker", "Скрыть приветственный стикер", s.hideGreetingSticker, true),
            .toggle(27, 4, "mentionComma", "Запятая после упоминания", s.commaAfterMention, true),
            .toggle(28, 4, "mentionAvatars", "Аватарки в упоминаниях", s.mentionAvatars, true),
            .toggle(29, 4, "pollResultsBeforeVoting", "Итоги до голосования", s.showPollResultsBeforeVoting, true),
            .toggle(30, 4, "channelForwardCount", "Счетчик пересылок в каналах", s.showChannelForwardCount, true),
            .toggle(31, 4, "forwardDate", "Время пересылки", s.showForwardDate, true),
            .toggle(32, 4, "removePings", "Убрать пинги", s.removePings, true),
            .toggle(33, 4, "hideViaBot", "Скрыть «Via Bot» в сообщении", s.hideViaBot, true),
            .toggle(34, 4, "removeLinkPreviews", "Удалить превью-ссылки", s.removeLinkPreviews, true),
            .header(35, 5, "ГОЛОС В ТЕКСТ"),
            .disclosure(36, 5, "transcription", "Сервис", transcription),
            .header(38, 6, "ЗАПИСЬ"),
            .disclosure(39, 6, "camera", "Камера в кружках", cameraTitle),
            .toggle(40, 6, "rememberCamera", "Запоминать последнюю камеру", s.rememberRoundVideoCamera, true),
            .toggle(41, 6, "zoomSlider", "Слайдер зума", s.roundVideoZoomSlider, true),
            .toggle(42, 6, "staticZoom", "Оставлять зум после щипка", s.staticRoundVideoZoom, true),
            .disclosure(43, 6, "pauseMusicOnRecording", "Пауза музыки при записи", "\(musicOptions.filter { s.musicPlaybackExceptions.contains($0) }.count)/3"),
            .toggle(44, 6, "builtInMic", "Встроенный микрофон", s.forceBuiltInMicrophone, true),
            .header(48, 7, "ВИДЕО"),
            .disclosure(49, 7, "doubleTapSeek", "Перемотка двойным нажатием", s.doubleTapSeekSeconds == 0 ? "Отключено" : "\(s.doubleTapSeekSeconds) сек."),
            .toggle(50, 7, "autoPause", "Авто пауза", s.autoPause, true),
            .disclosure(51, 7, "autoPauseMedia", "Приостанавливать", "\([1, 2, 4].filter { s.autoPauseMedia & $0 != 0 }.count)/3"),
            .header(58, 8, "КАНАЛЫ"),
            .toggle(59, 8, "wideChannelPosts", "Широкие посты в каналах", s.wideChannelPosts, true),
            .disclosure(60, 8, "channelBottomButton", "Нижняя кнопка", dgChannelBottomButtonTitle(s.channelBottomButton)),
            .header(68, 9, "ВОСПРОИЗВЕДЕНИЕ"),
            .toggle(69, 9, "autoplayMedia", "Отключить автовоспроизведение медиа", s.disableMediaAutoplay, true),
            .disclosure(70, 9, "autoplayMediaTypes", "Останавливать после", "\([1, 2].filter { s.disabledAutoplayMediaTypes & $0 != 0 }.count)/2"),
            .info(71, 9, "Если включено, следующее ГС или кружок не запустится автоматически."),
            .header(78, 10, "БОТЫ"),
            .toggle(79, 10, "hideBotAutomation", "Скрыть автоматизацию ботов", s.hideBotAutomation, true),
            .header(88, 11, "ДРУГОЕ"),
            .toggle(89, 11, "hideArchive", "Скрывать архив из списка чатов", s.hideArchive, true)
        ])
        result.append(.toggle(90, 11, "hideGiftButton", "Скрыть отправку подарка", s.hideGiftButton, true))
        result.append(.disclosure(91, 11, "glow", "Свечение", "\([s.avatarGlow, s.reactionGlow].filter { $0 }.count)/2"))
        result.append(.toggle(92, 11, "jumpToStart", "Кнопка «В начало чата»", s.jumpToStartInChatMenu, true))
        result.append(.info(93, 11, "Появляется в меню, если зажать аватарку в чате, и переносит к самому первому сообщению."))
        return result
    }, additionalUpdates: previewUpdates, toggle: { key, value in
        switch key {
        case "snow": s.forceSnow = value
        case "hideStatus": s.chatListHideStatus = value
        case "hideEmojiStatus": s.chatListHideEmojiStatus = value
        case "centerTitle": s.chatListCenteredTitle = value
        case "hideSearch": s.chatListHideSearch = value
        case "foldersAtBottom": s.chatListFoldersAtBottom = value
        case "hidePaidReactions": s.hidePaidReactions = value
        case "hideViaBot": s.hideViaBot = value
        case "removeLinkPreviews": s.removeLinkPreviews = value
        case "hideBotAutomation": s.hideBotAutomation = value
        case "autoplayMedia": s.disableMediaAutoplay = value
        case "onlyAdded": s.onlyAddedStickers = value
        case "recent": s.infiniteRecentStickers = value
        case "hideStickerTime": s.hideStickerTime = value
        case "hideStickerChecks": s.hideStickerChecks = value
        case "hideStickerReplyColors": s.hideStickerReplyColors = value
        case "hideStickerReplyEmoji": s.hideStickerReplyEmoji = value
        case "hideStickerReplyBackground": s.hideStickerReplyBackground = value
        case "hidePremiumReplyEmoji": s.hidePremiumReplyEmoji = value
        case "tails": s.removeMessageTails = value
        case "seconds": s.showMessageSeconds = value
        case "replies": s.disableColoredReplies = value
        case "editedIcon": s.editedIcon = value
        case "onlineIndicator": s.showOnlineIndicator = value
        case "greetingSticker": s.hideGreetingSticker = value
        case "mentionComma": s.commaAfterMention = value
        case "mentionAvatars": s.mentionAvatars = value
        case "removePings": s.removePings = value
        case "pollResultsBeforeVoting": s.showPollResultsBeforeVoting = value
        case "channelForwardCount": s.showChannelForwardCount = value
        case "forwardDate": s.showForwardDate = value
        case "wideChannelPosts": s.wideChannelPosts = value
        case "rememberCamera": s.rememberRoundVideoCamera = value
        case "zoomSlider": s.roundVideoZoomSlider = value
        case "staticZoom": s.staticRoundVideoZoom = value
        case "builtInMic": s.forceBuiltInMicrophone = value
        case "autoPause": s.autoPause = value
        case "hideArchive": s.hideArchive = value
        case "hideGiftButton": s.hideGiftButton = value
        case "jumpToStart": s.jumpToStartInChatMenu = value
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
        case "glow": return dgGlowController(context: context)
        case "transcription": return dgTranscriptionController(context: context)
        case "camera": return dgRoundVideoCameraController(context: context)
        case "autoplayMediaTypes": return dgAutoplayMediaController(context: context)
        case "autoPauseMedia": return dgAutoPauseMediaController(context: context)
        case "doubleTapSeek": return dgDoubleTapSeekController(context: context)
        case "titleMode": return dgChatListTitleModeController(context: context)
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

// Keep previously shared links opening the controls at their new inline location.
private func dgChatListAppearanceController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    return dgChatsSettingsController(context: context, focusKey: focusKey ?? "chatListPreview")
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

private func dgAutoplayMediaController(context: AccountContext, focusKey: String? = nil) -> ViewController {
    let s = DGSimpleSettings.shared
    return dgController(context: context, page: .autoplayMedia, title: "Отключить автовоспроизведение медиа", focusKey: focusKey, entries: {
        [.toggle(0, 0, "1", "Голосовые", s.disabledAutoplayMediaTypes & 1 != 0, s.disableMediaAutoplay),
         .toggle(1, 0, "2", "Кружки", s.disabledAutoplayMediaTypes & 2 != 0, s.disableMediaAutoplay)]
    }, toggle: { key, value in
        guard let mask = Int(key) else { return }
        s.disabledAutoplayMediaTypes = value ? (s.disabledAutoplayMediaTypes | mask) : (s.disabledAutoplayMediaTypes & ~mask)
    })
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
    if page == .chats && key == "openArchiveOnPull" {
        // Links to rows that are gone lead to the switches that replaced them.
        focusKey = "hideArchive"
    } else if page == .chats && key == "chatListAppearance" {
        focusKey = "chatListPreview"
    } else if page == .chats && key == "stickerReplies" {
        focusKey = "hideStickerReplyColors"
    } else if page == .appearance && key == "dialogIdFormat" && !DGSimpleSettings.shared.showProfileId {
        focusKey = "profileId"
    } else if page == .general && key == "saveOwnDeleted" && !DGSimpleSettings.shared.saveDeletedMessages {
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
    case .autoplayMedia: makeController = dgAutoplayMediaController
    case .autoPause: makeController = dgAutoPauseMediaController
    case .musicPlaybackExceptions: makeController = dgMusicPlaybackExceptionsController
    case .downloads: makeController = dgDownloadsSettingsController
    case .transcription: makeController = dgTranscriptionController
    case .reactions: makeController = dgHiddenReactionsController
    case .stickerReplies: makeController = { context, _ in
        dgChatsSettingsController(context: context, focusKey: "hideStickerReplyColors")
    }
    case .glow: makeController = dgGlowController
    case .visualId: makeController = dgVisualIdController
    case .visualRating: makeController = dgVisualRatingController
    case .visualUsernames: makeController = dgVisualUsernamesController
    case .visualPhone: makeController = dgVisualPhoneController
    case .shadowBan: makeController = dgShadowBanController
    case .savedDeleted: makeController = dgSavedDeletedMessagesController
    case .support: makeController = dgSupportController
    }
    return makeController(context, focusKey)
}
