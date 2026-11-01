import Foundation
import DGSimpleSettings

struct DGSettingsSearchItem {
    let index: Int32
    let page: String
    let key: String
    let title: String
    let section: String
    let group: String
    let words: [String]

    init(index: Int32, page: String, key: String, title: String, section: String, group: String) {
        self.index = index
        self.page = page
        self.key = key
        self.title = title
        self.section = section
        self.group = group
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

func dgSettingsSearchItems(query: String, hasIsland: Bool) -> [DGSettingsSearchItem] {
    let words = dgSettingsSearchWords(query)
    guard !words.isEmpty else { return [] }
    return dgSettingsSearchCatalog.compactMap { item in
        var item = item
        if !hasIsland && item.page == "icon-and-island" {
            if ["islandFollowsIcon", "islandStyle"].contains(item.key) {
                return nil
            }
            item = DGSettingsSearchItem(index: item.index, page: item.page, key: item.key, title: "Иконка приложения", section: item.key.isEmpty ? "Настройки Donutgram" : "Иконка приложения", group: "")
        }
        return words.allSatisfy { word in item.words.contains { $0.contains(word) } } ? item : nil
    }
}

let dgSettingsSearchCatalog: [DGSettingsSearchItem] = {
    var result: [DGSettingsSearchItem] = []
    func add(_ page: String, _ title: String, _ rows: [(String, String, String)]) {
        result.append(DGSettingsSearchItem(index: Int32(result.count), page: page, key: "", title: title, section: "Настройки Donutgram", group: ""))
        for (key, rowTitle, group) in rows {
            result.append(DGSettingsSearchItem(index: Int32(result.count), page: page, key: key, title: rowTitle, section: title, group: group))
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
        ("disappearedGifts", "Видеть удалённые подарки", "ДРУГОЕ"),
        ("keepBannedChats", "Оставлять чаты после бана", "ДРУГОЕ")
    ])
    add("bypass", "Обход ограничений", [
        ("bypassForward", "Пересылка из защищённых чатов", "ПЕРЕСЫЛКА"),
        ("protectedScreenshots", "Скриншоты в защищённых чатах", "ЗАЩИЩЁННОЕ СОДЕРЖИМОЕ"),
        ("saveProtectedStories", "Сохранять защищённые истории", "ЗАЩИЩЁННОЕ СОДЕРЖИМОЕ"),
        ("gifUnlock", "Обход блокировок GIF", "GIF"),
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
        ("foldersAtBottom", "Папки внизу", "СПИСОК"),
        ("hideArchive", "Скрыть архив из списка чатов", "СПИСОК"),
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
        ("removePings", "Упоминания как обычные сообщения", "УПОМИНАНИЯ"),
        ("hideViaBot", "Скрыть «Via Bot» в сообщении", "СОДЕРЖИМОЕ"),
        ("hideServiceMessages", "Скрыть служебные сообщения", "СОДЕРЖИМОЕ"),
        ("greetingSticker", "Скрыть приветственный стикер", "СОДЕРЖИМОЕ"),
        ("pollResultsBeforeVoting", "Итоги до голосования", "СОДЕРЖИМОЕ"),
        ("hideBotAutomation", "Скрыть плашку чат-бота", "СОДЕРЖИМОЕ"),
        ("customBackgrounds", "Отключить кастомные фоны", "СОДЕРЖИМОЕ"),
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
    add("visual-id", "ID профиля", [
        ("visualId", "Любой текст", "ID ПРОФИЛЯ")
    ])
    add("visual-rating", "Рейтинг", [
        ("level", "Уровень", "")
    ])
    add("visual-usernames", "NFT-юзернеймы", [
        ("names", "Имена через запятую", "")
    ])
    add("visual-phone", "Номер телефона", [
        ("enabled", "Показывать другой номер", "ПОДМЕНА НОМЕРА"),
        ("number", "Номер телефона", "")
    ])
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
        ("downloadTikTok", "TikTok", "ВИДЕО ВМЕСТО ССЫЛКИ"),
        ("downloadShorts", "YouTube Shorts", "ВИДЕО ВМЕСТО ССЫЛКИ"),
        ("signDownloads", "Подпись «Скачано с …»", "ВИДЕО ВМЕСТО ССЫЛКИ"),
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
    add("about", "О Donutgram", [
        ("version", "Версия", "")
    ])
    return result
}()
