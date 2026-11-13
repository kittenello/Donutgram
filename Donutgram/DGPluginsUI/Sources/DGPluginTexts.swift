import Foundation
import DGPluginModel

// What the user reads about plugin errors, in Russian or English. The host's messages stay English: plugins and
// diagnostics consume them, and the codes are stable while these texts may change.

private func dgPluginTr(_ russian: Bool, _ ru: String, _ en: String) -> String {
    return russian ? ru : en
}

/// The title of a plugin's notice. The plugin chooses its own name, so the title always says it is a plugin: a plugin
/// named «Telegram» must not show a notice that looks like Telegram's.
public func dgPluginNoticeTitle(pluginName: String?, russian: Bool) -> String {
    let prefix = dgPluginTr(russian, "Плагин", "Plugin")
    guard let pluginName, !pluginName.isEmpty else { return prefix }
    return prefix + " · " + pluginName
}

/// The explanation of a failed plugin operation for an alert.
public func dgPluginErrorDescription(_ error: DGPluginError, russian: Bool) -> String {
    let tr = { (ru: String, en: String) in dgPluginTr(russian, ru, en) }
    switch error.message {
    case "only a newer reviewed version can replace this installation":
        return tr("Заменить установленный плагин можно только более новой версией.", "Only a newer version can replace this plugin.")
    case "finish removing the previous installation first":
        return tr("Сначала должно завершиться удаление прежней версии.", "Wait until the previous version is removed.")
    case "changing execution profile requires removing the old installation and its data":
        return tr("У новой версии другой профиль. Удалите старую версию вместе с её данными и установите плагин заново.", "The new version has another profile. Remove the old version with its data and install the plugin again.")
    case "at most four plugin runtimes may run for one account", "active plugin runtime limit reached":
        return tr("Одновременно могут работать не больше четырёх плагинов.", "At most four plugins can run at once.")
    case "grant required permissions before enabling this plugin", "required permissions were revoked":
        return tr("Сначала выдайте плагину обязательные разрешения.", "Grant the plugin its required permissions first.")
    case "installation limit reached":
        return tr("Установлено максимальное число плагинов (32).", "The limit of 32 installed plugins is reached.")
    case "no previous installed version is available":
        return tr("Предыдущей версии нет.", "There is no previous version.")
    case "previous version is not eligible for rollback":
        return tr("К предыдущей версии вернуться нельзя.", "The previous version cannot be restored.")
    default:
        break
    }
    switch error.code {
    case "permission_denied":
        return tr("Telegram или разрешения плагина не позволяют это действие.", "Telegram or the plugin's permissions do not allow this action.")
    case "scope_denied":
        return tr("Это действие недоступно здесь: в этом чате, для этого сообщения или без выделенного текста.", "This action is unavailable here: in this chat, for this message or without selected text.")
    case "rate_limited":
        return tr("Плагин выполняет действия слишком часто. Подождите немного.", "The plugin is acting too often. Wait a moment.")
    case "timeout", "validation_timeout":
        return tr("Время ожидания истекло.", "The operation timed out.")
    case "network_error":
        return tr("Не удалось связаться с сервисом.", "The service could not be reached.")
    case "busy":
        return tr("Плагин ещё выполняет предыдущее действие. Попробуйте ещё раз.", "The plugin is still busy with a previous action. Try again.")
    case "stale_handle", "revision_conflict", "conflict":
        return tr("Данные изменились, пока плагин работал. Повторите действие.", "The data changed while the plugin was working. Try again.")
    case "feature_unavailable":
        return tr("Эта возможность недоступна в этой сборке или на этом экране.", "This feature is unavailable in this build or on this screen.")
    case "runtime_error":
        return tr("Плагин остановлен: он превысил лимиты или завершился с ошибкой. Причина — в журнале ошибок в его настройках.", "The plugin was stopped: it exceeded its limits or failed. The reason is in its error history.")
    case "plugin_disabled":
        return tr("Плагин выключен или ещё запускается.", "The plugin is turned off or still starting.")
    case "quota_exceeded":
        return tr("Плагин превысил лимит.", "The plugin exceeded a limit.")
    case "storage_error":
        return tr("Не удалось сохранить данные плагинов.", "Plugin data could not be saved.")
    case "integrity_error":
        return tr("Файл плагина изменился после проверки. Откройте его снова.", "The plugin file changed after it was checked. Open it again.")
    case "send_failed":
        return tr("Сообщение не поставлено в очередь отправки.", "The message was not queued for sending.")
    case "edit_failed":
        return tr("Telegram не принял изменение сообщения.", "Telegram rejected the edit.")
    case "signature_mismatch":
        return tr("Подпись плагина не совпадает с его содержимым.", "The plugin's signature does not match its content.")
    case "incompatible":
        return tr("Плагин не подходит для этой версии Donutgram.", "The plugin does not fit this version of Donutgram.")
    case "source_revoked":
        return tr("Издатель этого плагина заблокирован на устройстве.", "This plugin's publisher is blocked on this device.")
    case "publisher_changed":
        return tr("У новой версии другой издатель. Удалите старую версию перед установкой.", "The new version has another publisher. Remove the old version first.")
    case "download_failed":
        return tr("Не удалось загрузить файл плагина.", "The plugin file could not be downloaded.")
    case "package_too_large", "package_limit":
        return tr("Файл плагина больше 8 МБ.", "The plugin file is larger than 8 MB.")
    case "not_plugin":
        return tr("Этот файл не является плагином.", "This file is not a plugin.")
    case "invalid_argument", "invalid_metadata", "invalid_manifest", "invalid_archive", "invalid_entry", "invalid_source", "invalid_path",
         "invalid_signature", "unknown_field", "unsupported_resource", "invalid_permissions", "invalid_settings", "invalid_identity",
         "invalid_origin", "invalid_profile", "invalid_icon", "invalid_package":
        return tr("Файл плагина повреждён или не соответствует формату", "The plugin file is damaged or does not follow the format") + " (" + error.code + ")."
    default:
        return tr("Плагин сообщил об ошибке: ", "The plugin reported an error: ") + error.code
    }
}

/// A reason the host stored (a plugin's last error, an error-history entry or a persistence problem).
/// History entries start with their ISO 8601 time, which is kept.
public func dgPluginStoredReason(_ text: String, russian: Bool) -> String {
    if let space = text.firstIndex(of: " "), text[..<space].contains("T"), text[..<space].count >= 20 {
        return String(text[..<space]) + " " + dgPluginStoredReason(String(text[text.index(after: space)...]), russian: russian)
    }
    let tr = { (ru: String, en: String) in dgPluginTr(russian, ru, en) }
    switch text {
    case "plugin activation failed or exceeded its budget":
        return tr("Плагин не запустился: ошибка или превышен лимит при запуске.", "The plugin did not start: it failed or ran over its limit while starting.")
    case "plugin could not start":
        return tr("Плагин не удалось запустить.", "The plugin could not be started.")
    case "plugin event handlers failed five times in a row":
        return tr("Обработчики событий плагина пять раз подряд завершились ошибкой.", "The plugin's event handlers failed five times in a row.")
    case "plugin event handler exceeded its budget or stopped", "plugin event handler failed or exceeded its budget":
        return tr("Обработчик событий превысил лимит или остановился.", "An event handler exceeded its limit or stopped.")
    case "outgoing message handler timed out":
        return tr("Обработка сообщения перед отправкой заняла слишком много времени.", "Processing a message before sending took too long.")
    case "outgoing message handler exceeded its budget or stopped", "outgoing message handler failed":
        return tr("Обработчик сообщений перед отправкой превысил лимит или остановился.", "The before-send handler exceeded its limit or stopped.")
    case "outgoing message handlers failed three times in a row":
        return tr("Обработчик сообщений перед отправкой три раза подряд завершился ошибкой.", "The before-send handler failed three times in a row.")
    case "plugin view-model transform exceeded its budget or stopped", "plugin view-model transform failed or exceeded its budget":
        return tr("Изменение экрана превысило лимит или остановилось.", "A screen transform exceeded its limit or stopped.")
    case "plugin view-model transforms repeatedly failed":
        return tr("Изменение экрана три раза подряд завершилось ошибкой.", "A screen transform failed three times in a row.")
    case "plugin command exceeded its budget or stopped", "plugin command failed or exceeded its budget":
        return tr("Команда плагина превысила лимит или остановилась.", "A plugin command exceeded its limit or stopped.")
    case "plugin interface callback exceeded its budget or stopped", "plugin interface callback failed":
        return tr("Действие на странице плагина превысило лимит или остановилось.", "An action on the plugin's page exceeded its limit or stopped.")
    case "the app closed unexpectedly while this plugin was running, so it was turned off":
        return tr("Приложение закрылось с ошибкой сразу после запуска плагина, поэтому он выключен. Включите его снова, если сбой не связан с ним.", "The app closed unexpectedly right after the plugin started, so it was turned off. Turn it on again if it was not the cause.")
    case "plugin state requires recovery; execution is stopped":
        return tr("Данные плагинов повреждены, выполнение остановлено.", "Plugin data needs recovery; execution is stopped.")
    case "unable to save the global switch; execution remains stopped for this session":
        return tr("Не удалось сохранить переключатель, плагины остановлены до перезапуска.", "The switch could not be saved; plugins stay stopped until a restart.")
    case "unable to save plugin data; its latest changes may be lost after a restart":
        return tr("Не удалось сохранить данные плагинов, последние изменения могут потеряться после перезапуска.", "Plugin data could not be saved; the latest changes may be lost after a restart.")
    default:
        return text
    }
}

/// The name of a capability as the user reads it, wherever a permission is shown or asked for.
func dgPluginPermissionTitle(_ capability: String, russian: Bool) -> String {
    let tr = { (ru: String, en: String) in dgPluginTr(russian, ru, en) }
    switch capability {
    case "ui.contribute": return tr("Команды и панели", "Commands and panels")
    case "ui.transform": return tr("Локальное оформление экранов", "Local screen appearance")
    case "theme.read": return tr("Текущая тема", "Current theme")
    case "theme.contribute": return tr("Локальные цвета и оформление", "Local colors and decorations")
    case "composer.read": return tr("Текст открытого черновика", "Text in the open draft")
    case "composer.transform": return tr("Изменение открытого черновика", "Change the open draft")
    case "messages.selection.read": return tr("Выделенный текст или всё выбранное сообщение", "Selected text or the whole message you choose")
    case "messages.read": return tr("Сообщения в выбранных чатах", "Messages in selected chats")
    case "chats.metadata.read": return tr("Названия выбранных чатов", "Selected chat names")
    case "peers.read": return tr("Данные выбранных контактов", "Selected contact details")
    case "storage.local": return tr("Собственные локальные данные", "Own local data")
    case "network.public": return tr("Публичные интернет-сервисы", "Public internet services")
    case "translation.request": return tr("Перевод выбранного текста", "Translate selected text")
    case "navigation.open": return tr("Открытие разрешённых экранов", "Open allowed screens")
    case "notifications.local": return tr("Локальные уведомления", "Local notifications")
    case "files.userSelected": return tr("Выбранный вами файл", "File you choose")
    case "messages.compose": return tr("Подготовка сообщения", "Prepare a message")
    case "messages.send": return tr("Отправка без дополнительного подтверждения", "Send without an additional confirmation")
    case "messages.edit": return tr("Замена текста выбранных сообщений, форматирование не сохраняется", "Replace the text of messages you choose; formatting is not kept")
    case "messages.delete": return tr("Удаление выбранных сообщений у всех", "Delete selected messages for everyone")
    case "messages.intercept": return tr("Изменение текста перед отправкой", "Change text before sending")
    case "messages.sendInteractive": return tr("Отправка с вашим подтверждением", "Send with your confirmation")
    default: return capability
    }
}

/// What the signature says about a plugin. The installer checks it only against the key in the same package and there is
/// no list of trusted publishers, so a signature proves that updates come from the same key, not who the author is: a
/// signed plugin names the last characters of its key (`publisher`, "ed25519:" + 64 hex digits) and its manifest's author
/// stays unconfirmed. Without a signature the author is only a claim, so the claim is never shown on its own.
func dgPluginTrustNote(_ trust: String, hasAuthor: Bool, publisher: String?, russian: Bool) -> String {
    switch trust {
    case "signatureVerified", "verified":
        let key: String? = publisher.flatMap { identity in identity.hasPrefix("ed25519:") && identity.count == 72 && identity.dropFirst(8).allSatisfy({ $0.isHexDigit }) ? String(identity.suffix(8)) : nil }
        let signed = key.map { dgPluginTr(russian, "Подписан ключом …", "Signed with key …") + $0 } ?? dgPluginTr(russian, "Подписан ключом издателя", "Signed with the publisher's key")
        return hasAuthor ? signed + dgPluginTr(russian, " · автор не подтверждён", " · author not confirmed") : signed
    case "revoked": return dgPluginTr(russian, "Издатель заблокирован на этом устройстве", "Publisher blocked on this device")
    default: return hasAuthor ? dgPluginTr(russian, "Автор не подтверждён: файл без подписи", "Author not confirmed: the file is unsigned") : dgPluginTr(russian, "Файл без подписи", "The file is unsigned")
    }
}

/// Whether a permission is required, followed by the exact services a network permission reaches: the reason is the
/// plugin's own text, the origins are what the host enforces.
func dgPluginPermissionDetail(_ permission: DGPluginPermission, required: Bool, russian: Bool) -> String {
    let kind = required ? dgPluginTr(russian, "Обязательное", "Required") : dgPluginTr(russian, "Необязательное", "Optional")
    return permission.origins.isEmpty ? kind : kind + " · " + permission.origins.joined(separator: ", ")
}
