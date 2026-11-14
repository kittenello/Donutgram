import Foundation
import DGSimpleSettings

struct DGSettingsSearchItem {
    let index: Int32
    let page: String
    let key: String
    let title: String
    let section: String
    let group: String
    // The words of the title alone, which rank the result, and of the title, section and group together, which find it,
    // in Russian and in English.
    let titleWords: [String]
    let words: [String]

    init(index: Int32, page: String, key: String, title: String, section: String, group: String) {
        self.index = index
        self.page = page
        self.key = key
        self.title = title
        self.section = section
        self.group = group
        self.titleWords = dgSettingsSearchWords(title + " " + dgLocalized(title, languageCode: "en"))
        let texts = [title, section, group]
        self.words = dgSettingsSearchWords((texts + texts.map { dgLocalized($0, languageCode: "en") }).joined(separator: " "))
    }

    var id: String { return page + "/" + key }

    func path(languageCode: String) -> String {
        return [section, group].filter { !$0.isEmpty }.map { dgLocalized($0, languageCode: languageCode) }.joined(separator: " > ")
    }
}

func dgSettingsSearchWords(_ text: String) -> [String] {
    return text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
}

/// The rows a query finds: each word of the query starts a word of the row's title, section or group, in either language.
/// The sections the query names come first, then the rows it names, then the rows of the sections and groups it names.
func dgSettingsSearchItems(query: String, hasIsland: Bool) -> [DGSettingsSearchItem] {
    let words = dgSettingsSearchWords(query)
    guard !words.isEmpty else { return [] }
    // Only the start of a word: inside words «id» would find every «Hide» and «Video», «фон» every «телефон».
    func matches(_ itemWords: [String]) -> Bool {
        return words.allSatisfy { word in itemWords.contains { $0.hasPrefix(word) } }
    }
    let found: [DGSettingsSearchItem] = dgSettingsSearchCatalog.compactMap { item in
        var item = item
        if !hasIsland && item.page == "icon-and-island" {
            // Without an island the page is the icon picker alone, so the section is the one result for it.
            guard item.key.isEmpty else {
                return nil
            }
            item = DGSettingsSearchItem(index: item.index, page: item.page, key: item.key, title: "Иконка приложения", section: "Настройки Donutgram", group: "")
        }
        return matches(item.words) ? item : nil
    }
    let ranked = found.map { item -> (rank: Int, item: DGSettingsSearchItem) in
        if matches(item.titleWords) {
            return (item.key.isEmpty ? 0 : 1, item)
        }
        return (2, item)
    }
    return ranked.sorted { ($0.rank, $0.item.index) < ($1.rank, $1.item.index) }.map { $0.item }
}

let dgSettingsSearchCatalog: [DGSettingsSearchItem] = {
    var result: [DGSettingsSearchItem] = []
    // A section of the root is found by its name as well. A screen opened from a row of a section (`parent`) is not:
    // that row already leads to it. Its rows show the way through the section and the screen instead.
    func add(_ page: String, _ title: String, _ rows: [(String, String, String)], parent: String? = nil) {
        if parent == nil {
            result.append(DGSettingsSearchItem(index: Int32(result.count), page: page, key: "", title: title, section: "Настройки Donutgram", group: ""))
        }
        for (key, rowTitle, group) in rows {
            result.append(DGSettingsSearchItem(index: Int32(result.count), page: page, key: key, title: rowTitle, section: parent ?? title, group: parent == nil ? group : title))
        }
    }
    add("ghost", "Режим призрака", [
        ("enabled", "Режим призрака", ""),
        ("messages", "Скрывать прочтение сообщений", "ЧТО СКРЫВАТЬ"),
        ("storyViews", "Скрывать просмотр историй", "ЧТО СКРЫВАТЬ"),
        ("online", "Скрывать «в сети»", "ЧТО СКРЫВАТЬ"),
        ("offline", "Автоматический «офлайн»", "ЧТО СКРЫВАТЬ"),
        ("typing", "Скрывать «печатает»", "ЧТО СКРЫВАТЬ"),
        ("readOnAction", "Читать чат при отправке", "ПОВЕДЕНИЕ"),
        ("scheduled", "Отправлять как отложенные", "ПОВЕДЕНИЕ"),
        ("silent", "Отправлять без звука", "ДРУГОЕ"),
        ("stories", "Предлагать призрака для историй", "ДРУГОЕ"),
        ("readAll", "Прочитать все на сервере", "ЧТЕНИЕ"),
        ("readAllLocal", "Прочитать все локально", "ЧТЕНИЕ")
    ])
    add("saving", "Удалённые и правки", [
        ("savedDeleted", "Сохранённые удалённые", "ХРАНИЛИЩЕ"),
        ("saveDeleted", "Сохранять удалённые сообщения", "СООБЩЕНИЯ"),
        ("saveOwnDeleted", "Сохранять свои удалённые", "СООБЩЕНИЯ"),
        ("transparentDeleted", "Полупрозрачные удалённые", "СООБЩЕНИЯ"),
        ("saveEdits", "Сохранять историю правок", "СООБЩЕНИЯ"),
        ("saveBots", "Сохранять в чатах с ботами", "СООБЩЕНИЯ"),
        ("saveOnce", "Сохранять одноразовые медиа", "ДРУГОЕ"),
        ("keepBannedChats", "Оставлять чаты после бана", "ДРУГОЕ"),
        ("disappearedGifts", "Видеть удалённые подарки", "ДРУГОЕ")
    ])
    add("bypass", "Обход ограничений", [
        ("bypassForward", "Пересылка из защищённых чатов", "ПЕРЕСЫЛКА"),
        ("protectedScreenshots", "Скриншоты в защищённых чатах", "ЗАЩИЩЁННОЕ СОДЕРЖИМОЕ"),
        ("saveProtectedStories", "Сохранять защищённые истории", "ЗАЩИЩЁННОЕ СОДЕРЖИМОЕ"),
        ("gifUnlock", "Обход блокировок GIF", "GIF"),
        ("stickerUnlock", "Обход блокировки стикеров", "СТИКЕРЫ"),
        ("bypassContentRestrictions", "Обход ограничений контента", "ОГРАНИЧЕННЫЙ КОНТЕНТ")
    ])
    add("shadow-ban", "Теневой бан", [
        ("hideBlocked", "Скрывать сообщения заблокированных", "")
    ])
    add("main-screen", "Список чатов", [
        ("snow", "Снег", "ЗАГОЛОВОК"),
        ("titleMode", "Текст в заголовке", "ЗАГОЛОВОК"),
        ("centerTitle", "Заголовок по центру", "ЗАГОЛОВОК"),
        ("hideEmojiStatus", "Скрыть эмодзи-статус", "ЗАГОЛОВОК"),
        ("hideStatus", "Скрыть статус соединения", "ЗАГОЛОВОК"),
        ("hideSearch", "Скрыть строку поиска", "ЗАГОЛОВОК"),
        ("neutralComposeButton", "Обычный цвет кнопки нового сообщения", "ЗАГОЛОВОК"),
        ("foldersAtBottom", "Папки внизу", "СПИСОК"),
        ("hideArchive", "Скрыть архив из списка чатов", "СПИСОК"),
        ("hideEmptyReplyDrafts", "Скрывать черновик пустого ответа", "СПИСОК"),
        ("hideStories", "Скрыть истории", "СПИСОК"),
        ("disableStoryCameraSwipe", "Отключить камеру по свайпу", "СПИСОК"),
        ("onlineIndicator", "Показывать индикатор онлайна", "СПИСОК"),
        ("avatarGlow", "Свечение аватарок", "СПИСОК"),
        ("hideTabBar", "Скрыть панель вкладок", "ВКЛАДКИ"),
        ("contacts", "Вкладка «Контакты»", "ВКЛАДКИ"),
        ("calls", "Вкладка «Звонки»", "ВКЛАДКИ"),
        ("wideTabBar", "Широкая панель вкладок", "ВКЛАДКИ")
    ])
    add("messages", "Сообщения", [
        ("tails", "Убрать хвост у сообщений", "ПУЗЫРИ"),
        ("seconds", "Показывать секунды", "ПУЗЫРИ"),
        ("editedIcon", "Заменять «изменено» иконкой", "ПУЗЫРИ"),
        ("replies", "Отключить цветные ответы", "ПУЗЫРИ"),
        ("hidePremiumReplyEmoji", "Скрыть премиум-эмодзи в ответах", "ПУЗЫРИ"),
        ("mentionComma", "Запятая после упоминания", "ПУЗЫРИ"),
        ("mentionAvatars", "Аватарки в упоминаниях", "ПУЗЫРИ"),
        ("forwardDate", "Дата оригинала в пересланных", "ПУЗЫРИ"),
        ("blurMessages", "Блюр сообщений", "ФОН СООБЩЕНИЙ"),
        ("removePings", "Упоминания как обычные сообщения", "УПОМИНАНИЯ"),
        ("hideViaBot", "Скрыть «Via Bot» в сообщении", "СОДЕРЖИМОЕ"),
        ("hideServiceMessages", "Скрыть служебные сообщения", "СОДЕРЖИМОЕ"),
        ("greetingSticker", "Скрыть приветственный стикер", "СОДЕРЖИМОЕ"),
        ("pollResultsBeforeVoting", "Итоги до голосования", "СОДЕРЖИМОЕ"),
        ("hideBotAutomation", "Скрыть плашку автоматизации", "СОДЕРЖИМОЕ"),
        ("customBackgrounds", "Отключить кастомные фоны", "СОДЕРЖИМОЕ"),
        ("hideAIFeatures", "Скрыть функции ИИ", "СОДЕРЖИМОЕ"),
        ("hidePhoneNumberInChatTitle", "Скрыть номер в заголовке чата", "СОДЕРЖИМОЕ"),
        ("removeLinkPreviews", "Отправлять без превью ссылок", "ОТПРАВКА"),
        ("wideChannelPosts", "Широкие посты в каналах", "КАНАЛЫ"),
        ("channelForwardCount", "Счётчик пересылок у постов", "КАНАЛЫ"),
        ("channelBottomButton", "Нижняя кнопка", "КАНАЛЫ"),
        ("jumpToStart", "Кнопка «В начало чата»", "МЕНЮ АВАТАРКИ")
    ])
    add("stickers", "Стикеры и реакции", [
        ("hideStickerTime", "Скрыть время на стикерах", "СТИКЕРЫ"),
        ("hideStickerChecks", "Скрыть галочки на стикерах", "СТИКЕРЫ"),
        ("hideStickerReplyColors", "Ответ без цвета", "СТИКЕРЫ"),
        ("hideStickerReplyEmoji", "Ответ без эмодзи", "СТИКЕРЫ"),
        ("hideStickerReplyBackground", "Ответ без фона", "СТИКЕРЫ"),
        ("onlyAdded", "Показывать только добавленные стикеры", "ПАНЕЛЬ СТИКЕРОВ"),
        ("recent", "Недавние стикеры без лимита", "ПАНЕЛЬ СТИКЕРОВ"),
        ("hideTrendingStickers", "Скрыть популярные стикеры", "ПАНЕЛЬ СТИКЕРОВ"),
        ("hideTrendingEmoji", "Скрыть популярные эмодзи", "ПАНЕЛЬ СТИКЕРОВ"),
        ("anonymousStickerSending", "Анонимная отправка стикеров", "ОТПРАВКА"),
        ("reactionsInChannels", "Скрыть реакции в каналах", "РЕАКЦИИ"),
        ("reactionsInGroups", "Скрыть реакции в группах", "РЕАКЦИИ"),
        ("reactionsInPrivateChats", "Скрыть реакции в личных чатах", "РЕАКЦИИ"),
        ("hidePaidReactions", "Скрыть платные реакции", "РЕАКЦИИ"),
        ("reactionGlow", "Свечение реакций", "РЕАКЦИИ"),
        ("stickerSize", "Размер стикеров", "СТИКЕРЫ"),
        ("stickerShape", "Форма стикеров", "")
    ])
    add("profiles", "Профили", [
        ("profileId", "Показывать ID", "ID"),
        ("dialogIdFormat", "Формат ID", "ID"),
        ("dc", "Показывать дата-центр (DC)", "ИНФОРМАЦИЯ"),
        ("regDate", "Показывать дату регистрации", "ИНФОРМАЦИЯ"),
        ("chatDate", "Показывать дату создания чата", "ИНФОРМАЦИЯ"),
        ("mutualContact", "Показывать взаимный контакт", "ИНФОРМАЦИЯ"),
        ("hidePhoneNumber", "Скрыть номер телефона", "ИНФОРМАЦИЯ"),
        ("compactProfileMusicAndBalance", "Компактные музыка и баланс", "МУЗЫКА И БАЛАНС"),
        ("relativeOnlineTime", "Относительное время онлайна", "ВРЕМЯ В СЕТИ"),
        ("approximateLastSeen", "Примерный онлайн", "ВРЕМЯ В СЕТИ"),
        ("premiumStatuses", "Скрыть премиум-статусы", "ЗНАЧКИ У ИМЁН"),
        ("hideVerification", "Скрыть верификацию", "ЗНАЧКИ У ИМЁН")
    ])
    add("icon-and-island", "Иконка и остров", [
        ("islandFollowsIcon", "Остров как у иконки", ""),
        ("islandStyle", "Стиль острова", ""),
        ("appIcon", "Иконка приложения", "")
    ])
    add("local-profile", "Локальный профиль", [
        ("visualPhone", "Номер телефона", "ВИДНО ТОЛЬКО ВАМ"),
        ("visualRating", "Рейтинг", "ВИДНО ТОЛЬКО ВАМ"),
        ("visualUsernames", "NFT-юзернеймы", "ВИДНО ТОЛЬКО ВАМ"),
        ("visualId", "ID профиля", "ВИДНО ТОЛЬКО ВАМ"),
        ("visualLabel", "Метка", "ВИДНО ТОЛЬКО ВАМ"),
        ("localVerification", "Локальная верификация", "ВИДНО ТОЛЬКО ВАМ"),
        ("localPremium", "Локальный Telegram Premium", "PREMIUM")
    ])
    // «ID профиля» and «NFT-юзернеймы» hold only the field their row names, so the row is their result.
    add("visual-rating", "Рейтинг", [
        ("level", "Уровень", "")
    ], parent: "Локальный профиль")
    add("visual-phone", "Номер телефона", [
        ("enabled", "Показывать другой номер", "")
    ], parent: "Локальный профиль")
    add("media", "Запись и воспроизведение", [
        ("camera", "Камера в кружках", "КРУЖКИ"),
        ("zoomSlider", "Слайдер зума", "КРУЖКИ"),
        ("staticZoom", "Оставлять зум после щипка", "КРУЖКИ"),
        ("roundVideoCountdown", "Отсчёт перед записью", "КРУЖКИ"),
        ("builtInMic", "Встроенный микрофон", "ЗАПИСЬ"),
        ("pauseMusicRoundVideos", "При записи кружков", "ПАУЗА МУЗЫКИ"),
        ("pauseMusicVoiceRecording", "При записи голосовых", "ПАУЗА МУЗЫКИ"),
        ("pauseMusicVoicePlayback", "При прослушивании голосовых", "ПАУЗА МУЗЫКИ"),
        ("doubleTapSeek", "Перемотка", "ВИДЕО"),
        ("gifScrubber", "Перемотка GIF", "GIF"),
        ("disableProfileMusicAutoplay", "Не включать музыку автоматически", "МУЗЫКА В ПРОФИЛЕ"),
        ("autoPause", "Пауза при сворачивании", "АВТОПАУЗА"),
        ("autoPauseVideo", "Видео", "АВТОПАУЗА"),
        ("autoPauseVoice", "Голосовые", "АВТОПАУЗА"),
        ("autoPauseRound", "Кружки", "АВТОПАУЗА"),
        ("autoplayMedia", "Не включать следующее", "ПОСЛЕ ПРОСЛУШИВАНИЯ"),
        ("autoplayVoice", "После голосовых", "ПОСЛЕ ПРОСЛУШИВАНИЯ"),
        ("autoplayRound", "После кружков", "ПОСЛЕ ПРОСЛУШИВАНИЯ"),
        ("transcription", "Сервис расшифровки", "ГОЛОС В ТЕКСТ")
    ])
    add("downloads", "Загрузки и сеть", [
        ("downloadTikTok", "TikTok", "СКАЧИВАТЬ"),
        ("downloadShorts", "YouTube Shorts", "СКАЧИВАТЬ"),
        ("signDownloads", "Подпись «Скачано с …»", "СКАЧИВАТЬ"),
        ("accelerateUpload", "Ускорение отправки", "УСКОРЕНИЕ ЗАГРУЗКИ"),
        ("downloadAcceleration", "Ускорение загрузки", "")
    ])
    add("security", "Подтверждения и статистика", [
        ("confirmCalls", "Звонки", "ПОДТВЕРЖДЕНИЯ"),
        ("confirmReactionsInUnjoinedChats", "Реакции без вступления", "ПОДТВЕРЖДЕНИЯ"),
        ("confirmTelegramLinks", "Переход по ссылкам Telegram", "ПОДТВЕРЖДЕНИЯ"),
        ("confirmChatPreviewEntry", "Вход из предпросмотра", "ПОДТВЕРЖДЕНИЯ"),
        ("telegramStatistics", "Отправлять в Telegram", "СТАТИСТИКА")
    ])
    add("ads-and-gifts", "Реклама и подарки", [
        ("disableAds", "Отключить рекламу", "РЕКЛАМА"),
        ("hideProxySponsor", "Скрыть спонсора прокси", "РЕКЛАМА"),
        ("hideGiftButton", "Скрыть отправку подарка", "ПОДАРКИ"),
        ("hideBirthdayNotifications", "Скрыть уведомления о днях рождения", "ПОДАРКИ"),
        ("disableGiftStarsRedirect", "Не открывать звёзды после продажи", "ПОДАРКИ")
    ])
    add("plugins", "Плагины", [])
    add("about", "О Donutgram", [
        ("channel", "Канал", ""),
        ("sourceCode", "Исходный код", ""),
        ("pluginDocs", "Документация плагинов", ""),
        ("version", "Версия", "")
    ])
    return result
}()
