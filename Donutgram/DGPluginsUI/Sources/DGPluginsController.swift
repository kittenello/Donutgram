import Foundation
import UIKit
import ImageIO
import Display
import SwiftSignalKit
import AccountContext
import TelegramCore
import TelegramPresentationData
import ItemListUI
import PresentationDataUtils
import OverlayStatusController
import UndoUI
import DGPluginModel
import DGPluginInstaller
import DGPluginHost

private extension DGPluginJSON {
    var uiNumberValue: Double? { if case let .number(value) = self { return value }; return nil }
}

private extension String {
    /// The text with its first letter upper-cased, for status words shown on their own line.
    var dgSentenceStart: String { return self.prefix(1).uppercased() + self.dropFirst() }
}

private struct DGPluginRow: ItemListNodeEntry {
    enum Kind: Int32 { case header, text, disclosure, toggle, input, multiline, markdown, card, slider, stepper, image, action, destructive, plugin }
    let index: Int32
    var stableId: Int32 { return self.index * 16 + self.kind.rawValue }
    let section: ItemListSectionId
    let kind: Kind
    let key: String
    let title: String
    var detail: String = ""
    var value: Bool = false
    var enabled: Bool = true
    var iconKey: String = ""
    var number: Double = 0
    var minimum: Double = 0
    var maximum: Double = 1
    var step: Double = 1
    var epoch: Int = 0
    var maxText: Int = 4096
    var summary: String = ""
    var toggleEnabled: Bool = true

    static func < (lhs: DGPluginRow, rhs: DGPluginRow) -> Bool { return lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let page = arguments as! DGPluginPage
        let action = { if page.accepts(self.epoch) { page.action(self.key) } }
        let toggle: (Bool) -> Void = { if page.accepts(self.epoch) { page.toggle(self.key, $0) } }
        let input: (String) -> Void = { if page.accepts(self.epoch) { page.input(self.key, $0) } }
        let number: (Double) -> Void = { if page.accepts(self.epoch) { page.number(self.key, $0) } }
        switch self.kind {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: self.title, sectionId: self.section)
        case .text:
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.title), sectionId: self.section)
        case .disclosure:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: self.iconKey.isEmpty ? nil : page.icon(self.iconKey), title: self.title, label: self.detail, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, action: action)
        case .toggle:
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: self.iconKey.isEmpty ? nil : page.icon(self.iconKey, size: 32), title: self.title, text: self.detail.isEmpty ? nil : self.detail, value: self.value, enableInteractiveChanges: self.enabled, enabled: self.enabled, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: toggle)
        case .input:
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: self.key == "search" ? "" : self.title), text: self.detail, placeholder: self.title, type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: input, shouldUpdateText: { $0.utf16.count <= self.maxText }, action: {})
        case .multiline:
            return DGPluginNativeItem(theme: presentationData.theme, sectionId: self.section, content: .multiline(self.title, self.detail, self.maxText), scale: presentationData.fontSize.itemListBaseFontSize / 17, accentColor: page.renderedAccent, textUpdated: input)
        case .markdown:
            return DGPluginNativeItem(theme: presentationData.theme, sectionId: self.section, content: .markdown(self.title), scale: presentationData.fontSize.itemListBaseFontSize / 17)
        case .card:
            return DGPluginNativeItem(theme: presentationData.theme, sectionId: self.section, content: .card(page.icon(self.iconKey, size: 68), self.title, self.detail, page.cardDescription()), scale: presentationData.fontSize.itemListBaseFontSize / 17)
        case .plugin:
            let content = DGPluginListContent(icon: page.icon(self.iconKey, size: 44), title: self.title, subtitle: self.detail, description: self.summary, enabled: self.value, interactive: self.enabled, toggleEnabled: self.toggleEnabled, actions: [page.tr("Настройки", "Settings"), page.tr("Поделиться", "Share"), page.tr("Удалить", "Remove")])
            return DGPluginListItem(sectionId: self.section, theme: presentationData.theme, content: content, scale: presentationData.fontSize.itemListBaseFontSize / 17, open: action, toggle: { value in
                if page.accepts(self.epoch) { page.toggle("enabled:" + self.iconKey, value) }
            }, action: { index in
                guard page.accepts(self.epoch), (0 ..< 3).contains(index) else { return }
                page.action(["settings:", "share:", "remove:"][index] + self.iconKey)
            })
        case .slider, .stepper:
            return DGPluginNativeItem(theme: presentationData.theme, sectionId: self.section, content: .number(self.title, self.number, self.minimum, self.maximum, self.step, self.kind == .slider), scale: presentationData.fontSize.itemListBaseFontSize / 17, accentColor: page.renderedAccent, numberUpdated: number)
        case .image:
            if let image = page.renderedImages[self.iconKey] { return DGPluginNativeItem(theme: presentationData.theme, sectionId: self.section, content: .image(image, self.title), scale: presentationData.fontSize.itemListBaseFontSize / 17) }
            return DGPluginNativeItem(theme: presentationData.theme, sectionId: self.section, content: .markdown(page.tr("Изображение недоступно", "Image unavailable")), scale: presentationData.fontSize.itemListBaseFontSize / 17)
        case .action, .destructive:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: self.title, kind: self.kind == .destructive ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { if self.enabled { action() } })
        }
    }
}

private enum DGPluginPageMode {
    case list
    case details(String)
    case permissions(String)
    case settings(String)
    case advanced(String)
    case rendered(DGPluginRenderedState)
}

private final class DGPluginPresentedPage {
    weak var controller: ViewController?
    let token: UUID
    init(controller: ViewController, token: UUID) { self.controller = controller; self.token = token }
}

private final class DGPluginPage {
    let context: AccountContext
    let manager: DGPluginManager
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    weak var controller: ItemListController?
    var mode: DGPluginPageMode
    var query = ""
    var busy = false
    var observer: UUID?
    private var sequence = 0
    var notice: String?
    var renderedImages: [String: UIImage] = [:]
    var renderedAccent: UIColor?
    private var presentedPages: [String: DGPluginPresentedPage] = [:]
    private var pendingRemoval: DGPluginInstallation?

    init(context: AccountContext, mode: DGPluginPageMode) {
        self.context = context
        self.manager = DGPluginManager.shared(accountKey: String(context.account.id.int64))
        self.mode = mode
        self.observer = self.manager.observe { [weak self] in self?.refresh() }
    }

    deinit {
        if case let .rendered(state) = self.mode { state.close() }
        if let observer = self.observer { self.manager.removeObserver(observer) }
    }

    var russian: Bool {
        return self.context.sharedContext.currentPresentationData.with { $0 }.strings.primaryComponent.languageCode.hasPrefix("ru")
    }

    func tr(_ ru: String, _ en: String) -> String {
        return self.russian ? ru : en
    }

    func refresh() {
        self.sequence += 1
        self.revision.set(self.sequence)
    }

    func accepts(_ epoch: Int) -> Bool { return epoch == self.sequence && !self.busy }

    func bindNativeHost() {
        if case .rendered = self.mode { return }
        self.manager.nativeRequest = { [weak self] installationId, method, params, validity, completion in
            guard let self, let controller = self.controller, controller.isNodeLoaded, controller.view.window != nil, validity() else { completion(.failure(DGPluginError(code: "cancelled", message: "plugin management screen is not active"))); return }
            guard method == "ui.toast" else { completion(.failure(DGPluginError(code: "feature_unavailable", message: "this adapter requires an active chat"))); return }
            guard let values = params.objectValue, Set(values.keys) == ["text"], let text = values["text"]?.stringValue, !text.isEmpty, text.utf16.count <= 512 else { completion(.failure(DGPluginError(code: "invalid_argument", message: "invalid plugin notice"))); return }
            let name = dgPluginNoticeTitle(pluginName: self.installation(installationId)?.manifest.name, russian: self.russian)
            guard validity() else { completion(.failure(DGPluginError(code: "cancelled", message: "plugin stopped"))); return }
            // A toast, not a modal alert: notices never block the screen.
            controller.present(UndoOverlayController(presentationData: self.context.sharedContext.currentPresentationData.with { $0 }, content: .info(title: String(name.prefix(64)), text: text, timeout: nil, customUndoText: nil), elevatedLayout: false, action: { _ in return false }), in: .current)
            completion(.success(.null))
        }
        self.manager.nativeRender = { [weak self] installationId, page, pluginName, validity, assets, callback, onClose in
            guard let self, let owner = self.controller, owner.isNodeLoaded, owner.view.window != nil, validity(), let pageId = page.objectValue?["id"]?.stringValue else { return .failure(DGPluginError(code: "cancelled", message: "plugin management screen is not active")) }
            do {
                let key = installationId + ":" + pageId
                let token = UUID()
                let closed = { [weak self] in
                    if self?.presentedPages[key]?.token == token { self?.presentedPages.removeValue(forKey: key) }
                    onClose()
                }
                let rendered: ViewController
                if let existing = self.presentedPages[key]?.controller, try dgUpdatePluginRenderedController(existing, page: page, pluginName: pluginName, validity: validity, onCallback: callback, assetProvider: assets, onClose: closed) { rendered = existing }
                else {
                    rendered = try dgPluginRenderedController(context: self.context, page: page, pluginName: pluginName, validity: validity, onCallback: callback, assetProvider: assets, onClose: closed)
                    guard validity() else { return .failure(DGPluginError(code: "cancelled", message: "plugin page cancelled")) }
                    owner.present(rendered, in: .window(.root))
                }
                self.presentedPages[key] = DGPluginPresentedPage(controller: rendered, token: token)
                return .success({ [weak self, weak rendered] in
                    if let self { guard self.presentedPages[key]?.token == token else { return }; self.presentedPages.removeValue(forKey: key) }
                    rendered?.dismiss()
                })
            } catch let error as DGPluginError { return .failure(error) }
            catch { return .failure(DGPluginError(code: "invalid_argument", message: "invalid plugin page")) }
        }
    }

    func installation(_ id: String) -> DGPluginInstallation? {
        return self.manager.installations.first(where: { $0.id == id })
    }

    var title: String {
        switch self.mode {
        case .list: return self.tr("Плагины", "Plugins")
        case .permissions: return self.tr("Возможности плагина", "Plugin capabilities")
        case .settings: return self.tr("Настройки плагина", "Plugin settings")
        case .advanced: return self.tr("Дополнительно", "Advanced")
        case let .details(id): return self.installation(id)?.manifest.name ?? self.tr("Плагин удалён", "Plugin removed")
        case let .rendered(state): return state.title
        }
    }

    func rows() -> [DGPluginRow] {
        var rows: [DGPluginRow] = []
        func add(_ section: Int32, _ kind: DGPluginRow.Kind, _ key: String, _ title: String, detail: String = "", value: Bool = false, enabled: Bool = true, icon: String = "") {
            rows.append(DGPluginRow(index: Int32(rows.count), section: section, kind: kind, key: key, title: title, detail: detail, value: value, enabled: enabled && !self.busy, iconKey: icon))
        }
        switch self.mode {
        case .list:
            if let notice = self.notice { add(0, .text, "", notice) }
            if let error = self.manager.persistenceError { add(0, .text, "", dgPluginStoredReason(error, russian: self.russian)) }
            add(0, .toggle, "global", self.manager.globallyEnabled ? self.tr("Плагины включены", "Plugins enabled") : self.tr("Плагины выключены", "Plugins disabled"), value: self.manager.globallyEnabled, icon: "__plugins")
            let installations = self.manager.installations
            add(1, .input, "search", self.tr("Поиск", "Search"), detail: self.query)
            add(2, .header, "", self.tr("УСТАНОВЛЕННЫЕ", "INSTALLED"))
            let matches = installations.filter { self.query.isEmpty || ($0.manifest.name + " " + $0.manifest.id + " " + ($0.manifest.author?.name ?? "")).localizedCaseInsensitiveContains(self.query) }
            if matches.isEmpty {
                add(2, .text, "", self.query.isEmpty ? self.tr("Плагинов пока нет. Для установки откройте плагин в чате.", "No plugins yet. Open a plugin in a chat to install it.") : self.tr("Ничего не найдено", "Nothing found"))
            }
            for (index, item) in matches.enumerated() {
                let section = Int32(index + 2)
                let status = !self.manager.globallyEnabled || (item.enabled && item.state == .running) ? "" : " · " + self.stateText(item)
                rows.append(DGPluginRow(index: Int32(rows.count), section: section, kind: .plugin, key: "details:" + item.id, title: item.manifest.name, detail: (item.manifest.author?.name ?? self.tr("Автор не указан", "Author not specified")) + " · " + item.manifest.version + status, value: item.enabled, enabled: !self.busy, iconKey: item.id, summary: item.manifest.description, toggleEnabled: self.manager.globallyEnabled))
            }
        case let .details(id):
            guard let item = self.installation(id) ?? (self.pendingRemoval?.id == id ? self.pendingRemoval : nil) else { add(0, .text, "", self.tr("Этот плагин удалён.", "This plugin has been removed.")); break }
            self.appendCard(manifest: item.manifest, iconKey: id, add: add)
            add(4, .toggle, "enabled:" + id, self.tr("Включён", "Enabled"), value: item.enabled, enabled: self.manager.globallyEnabled)
            if self.manager.globallyEnabled { add(4, .text, "", self.stateText(item).dgSentenceStart) }
            if let error = item.lastError { add(4, .text, "", dgPluginStoredReason(error, russian: self.russian)) }
            add(5, .disclosure, "settings:" + id, self.tr("Настройки плагина", "Plugin settings"))
            add(5, .action, "share:" + id, self.tr("Поделиться", "Share"))
            let placements = Set(self.manager.commands.filter { $0.installationId == id }.map { $0.placement })
            var commandPlaces: [String] = []
            if !placements.isDisjoint(with: ["composer", "chatToolbar"]) { commandPlaces.append(self.tr("команды для чата — в меню, которое открывается долгим нажатием на аватар в шапке чата", "chat commands are in the menu that opens when you long-press the avatar in the chat header")) }
            if !placements.isDisjoint(with: ["messageMenu", "selection"]) { commandPlaces.append(self.tr("команды для сообщений — в меню сообщения", "message commands are in a message's menu")) }
            if !commandPlaces.isEmpty { add(6, .text, "", (commandPlaces.joined(separator: "; ") + ".").dgSentenceStart) }
            if let changelog = item.manifest.changelog, !changelog.isEmpty { add(7, .header, "", self.tr("ЧТО НОВОГО", "WHAT'S NEW")); add(7, .text, "", changelog) }
            add(8, .disclosure, "advanced:" + id, self.tr("Дополнительно", "Advanced"))
            add(9, .destructive, "remove:" + id, self.tr("Удалить плагин", "Remove plugin"))
        case let .advanced(id):
            guard let item = self.installation(id) else { break }
            add(0, .disclosure, "permissions:" + id, self.tr("Доступ к функциям", "Feature access"))
            add(1, .action, "reset:" + id, self.tr("Сбросить настройки и данные", "Reset settings and data"))
            add(2, .text, "", self.tr("Для обновления откройте новую версию плагина в чате.", "To update, open a new version of the plugin in a chat."))
            if self.manager.canRollback(id: id) { add(7, .action, "rollback:" + id, self.tr("Вернуться к предыдущей версии", "Restore previous version")) }
            if let publisher = self.manager.publisherIdentity(id: id), publisher.hasPrefix("ed25519:") {
                add(7, .action, "publisher:" + id, item.trust == "revoked" ? self.tr("Разблокировать издателя", "Unblock publisher") : self.tr("Заблокировать издателя", "Block publisher"))
            }
            let diagnostics = self.manager.diagnostics(id: id)
            if !diagnostics.isEmpty {
                add(8, .header, "", self.tr("ЖУРНАЛ ОШИБОК", "ERROR HISTORY"))
                for entry in diagnostics.prefix(20) { add(8, .text, "", String(dgPluginStoredReason(entry, russian: self.russian).prefix(512))) }
            }
        case let .permissions(id):
            guard let item = self.installation(id) else { break }
            for (index, permission) in (item.manifest.permissions + item.manifest.optionalPermissions).enumerated() {
                let section = Int32(index + 1)
                add(section, .toggle, "grant:\(index)", self.permissionTitle(permission.capability), value: item.grants.contains(permission))
                add(section, .text, "", permission.reason)
            }
        case let .settings(id):
            guard let item = self.installation(id) else { break }
            let properties = item.manifest.settingsSchema?.objectValue?["properties"]?.objectValue ?? [:]
            let commands = self.manager.commands.filter { $0.installationId == id && $0.placement == "settings" }
            for command in commands { add(0, .action, "command:" + command.id, command.title) }
            if properties.isEmpty && commands.isEmpty { add(0, .text, "", item.enabled ? self.tr("У плагина нет настроек.", "This plugin has no settings.") : self.tr("Включите плагин, чтобы открыть его настройки.", "Enable the plugin to open its settings.")) }
            for (index, key) in properties.keys.sorted().enumerated() {
                guard let schema = properties[key]?.objectValue else { continue }
                let title = schema["title"]?.stringValue ?? key
                let value = item.settings[key] ?? schema["default"] ?? .null
                let section = Int32(index + 1)
                if case .array? = schema["enum"] {
                    add(section, .disclosure, "enum:" + key, title, detail: self.settingText(value))
                    continue
                }
                switch schema["type"]?.stringValue {
                case "boolean":
                    add(section, .toggle, "setting:" + key, title, value: value == .bool(true))
                case "string":
                    let limit = Int(min(4096, max(0, schema["maxLength"]?.uiNumberValue ?? 4096)))
                    rows.append(DGPluginRow(index: Int32(rows.count), section: section, kind: .multiline, key: "setting:" + key, title: title, detail: self.settingText(value), maxText: limit))
                case "number", "integer":
                    let integer = schema["type"]?.stringValue == "integer"
                    let minimum = integer ? ceil(schema["minimum"]?.uiNumberValue ?? -1000000) : (schema["minimum"]?.uiNumberValue ?? -1000000)
                    let maximum = integer ? floor(schema["maximum"]?.uiNumberValue ?? 1000000) : (schema["maximum"]?.uiNumberValue ?? 1000000)
                    let number = value.uiNumberValue ?? max(minimum, min(maximum, 0))
                    let step = integer ? 1.0 : 0.1
                    if minimum.isFinite, maximum.isFinite, abs(minimum) <= 1e9, abs(maximum) <= 1e9, minimum < maximum, maximum - minimum >= step, number >= minimum, number <= maximum {
                        rows.append(DGPluginRow(index: Int32(rows.count), section: section, kind: .stepper, key: "setting:" + key, title: title, number: number, minimum: minimum, maximum: maximum, step: step))
                    } else { add(section, .input, "setting:" + key, title, detail: self.settingText(value)) }
                default:
                    add(section, .text, "", title + ": " + self.tr("этот тип настройки пока недоступен", "this setting type is unavailable"))
                }
                if let description = schema["description"]?.stringValue { add(section, .text, "", description) }
            }
        case let .rendered(state):
            guard state.validity() else { add(0, .text, "", self.tr("Плагин остановлен или доступ отозван. Закройте эту страницу.", "The plugin stopped or permission was revoked. Close this page.")); break }
            var section: Int32 = 1
            func append(_ nodes: [DGPluginRenderNode]) {
                for node in nodes {
                    let key = "render:" + node.id
                    let value = state.values[node.id] ?? node.value
                    switch node.type {
                    case "section", "list":
                        section += 1
                        if !node.title.isEmpty { add(section, .header, "", node.title) }
                        if !node.text.isEmpty { add(section, .text, "", node.text) }
                        append(node.children)
                        section += 1
                    case "text": add(section, .text, "", node.text.isEmpty ? node.title : node.text)
                    case "markdown": add(section, .markdown, "", node.text)
                    case "button": add(section, .action, key, node.title)
                    case "toggle": add(section, .toggle, key, node.title, value: value == .bool(true))
                    case "input": add(section, .input, key, node.title, detail: self.settingText(value))
                    case "multiline": add(section, .multiline, key, node.title, detail: self.settingText(value))
                    case "slider", "stepper":
                        rows.append(DGPluginRow(index: Int32(rows.count), section: section, kind: node.type == "slider" ? .slider : .stepper, key: key, title: node.title, number: value.uiNumberValue ?? node.minimum, minimum: node.minimum, maximum: node.maximum, step: node.step))
                    case "image": add(section, .image, "", node.title, icon: node.asset ?? "")
                    case "select": add(section, .disclosure, key, node.title, detail: node.options.first(where: { $0.value == value })?.title ?? self.settingText(value))
                    default: break
                    }
                }
            }
            append(state.nodes)
        }
        return rows.map { row in var row = row; row.epoch = self.sequence; return row }
    }

    private func appendCard(manifest: DGPluginManifest, iconKey: String, add: (Int32, DGPluginRow.Kind, String, String, String, Bool, Bool, String) -> Void) {
        let author = manifest.author.map { $0.name + ($0.username.map { " (@\($0))" } ?? "") } ?? self.tr("не указан", "not specified")
        add(0, .card, "", manifest.name, author + " · " + manifest.version, false, true, iconKey)
    }

    private func permissionTitle(_ capability: String) -> String {
        switch capability {
        case "ui.contribute": return self.tr("Команды и панели", "Commands and panels")
        case "ui.transform": return self.tr("Локальное оформление экранов", "Local screen appearance")
        case "theme.read": return self.tr("Текущая тема", "Current theme")
        case "theme.contribute": return self.tr("Локальные цвета и оформление", "Local colors and decorations")
        case "composer.read": return self.tr("Текст открытого черновика", "Text in the open draft")
        case "composer.transform": return self.tr("Изменение открытого черновика", "Change the open draft")
        case "messages.selection.read": return self.tr("Выделенный текст или всё выбранное сообщение", "Selected text or the whole message you choose")
        case "messages.read": return self.tr("Сообщения в выбранных чатах", "Messages in selected chats")
        case "chats.metadata.read": return self.tr("Названия выбранных чатов", "Selected chat names")
        case "peers.read": return self.tr("Данные выбранных контактов", "Selected contact details")
        case "storage.local": return self.tr("Собственные локальные данные", "Own local data")
        case "network.public": return self.tr("Публичные интернет-сервисы", "Public internet services")
        case "translation.request": return self.tr("Перевод выбранного текста", "Translate selected text")
        case "navigation.open": return self.tr("Открытие разрешённых экранов", "Open allowed screens")
        case "notifications.local": return self.tr("Локальные уведомления", "Local notifications")
        case "files.userSelected": return self.tr("Выбранный вами файл", "File you choose")
        case "messages.compose": return self.tr("Подготовка сообщения", "Prepare a message")
        case "messages.send": return self.tr("Отправка без дополнительного подтверждения", "Send without an additional confirmation")
        case "messages.edit": return self.tr("Замена текста выбранных сообщений, форматирование не сохраняется", "Replace the text of messages you choose; formatting is not kept")
        case "messages.delete": return self.tr("Удаление выбранных сообщений у всех", "Delete selected messages for everyone")
        case "messages.intercept": return self.tr("Изменение текста перед отправкой", "Change text before sending")
        case "messages.sendInteractive": return self.tr("Отправка с вашим подтверждением", "Send with your confirmation")
        default: return capability
        }
    }

    private func settingText(_ value: DGPluginJSON) -> String {
        switch value { case let .string(text): return text; case let .number(number): return String(number); case let .bool(value): return value ? self.tr("Да", "Yes") : self.tr("Нет", "No"); default: return "" }
    }

    private func stateText(_ item: DGPluginInstallation) -> String {
        if !self.manager.globallyEnabled { return self.tr("выполнение остановлено для всех плагинов", "all plugin execution is stopped") }
        switch item.state {
        case .running: return self.tr("работает", "running")
        case .starting: return self.tr("запускается", "starting")
        case .failed: return self.tr("ошибка выполнения", "execution failed")
        case .quarantined: return self.tr("изолирован после сбоя", "quarantined after failure")
        case .permissionRequired: return self.tr("нужны разрешения", "permissions required")
        case .incompatible: return self.tr("несовместим", "incompatible")
        case .updating: return self.tr("обновляется", "updating")
        case .removing, .removed: return self.tr("удаляется", "removing")
        default: return self.tr("выключен", "disabled")
        }
    }

    func cardDescription() -> String {
        switch self.mode {
        case let .details(id): return self.installation(id)?.manifest.description ?? self.pendingRemoval?.manifest.description ?? ""
        default: return ""
        }
    }

    func icon(_ key: String, size: CGFloat = 40) -> UIImage {
        let manifest = self.installation(key)?.manifest ?? (self.pendingRemoval?.id == key ? self.pendingRemoval?.manifest : nil)
        let data = self.manager.iconData(id: key)
        return dgPluginIcon(data: data, id: manifest?.id ?? key, name: manifest?.name ?? "dg", size: size)
    }

    func action(_ key: String) {
        guard !self.busy else { return }
        if key.hasPrefix("render:"), case let .rendered(state) = self.mode, let node = state.node(String(key.dropFirst(7))), state.validity() {
            if node.type == "select" {
                let actions = node.options.map { option in TextAlertAction(type: .genericAction, title: option.title, action: { [weak self, weak state] in
                    guard let self, let state, case let .rendered(current) = self.mode, current === state else { return }
                    state.invoke(node, value: option.value)
                    self.refresh()
                }) } + [TextAlertAction(type: .defaultAction, title: self.tr("Отмена", "Cancel"), action: {})]
                self.controller?.present(textAlertController(context: self.context, title: node.title, text: "", actions: actions), in: .window(.root))
            } else { state.invoke(node, value: .null) }
            return
        }
        if key.hasPrefix("details:") { self.push(.details(String(key.dropFirst(8)))); return }
        if key.hasPrefix("permissions:") { self.push(.permissions(String(key.dropFirst(12)))); return }
        if key.hasPrefix("settings:") { self.push(.settings(String(key.dropFirst(9)))); return }
        if key.hasPrefix("advanced:") { self.push(.advanced(String(key.dropFirst(9)))); return }
        if key.hasPrefix("share:") { self.share(String(key.dropFirst(6))); return }
        if key.hasPrefix("remove:") {
            let id = String(key.dropFirst(7))
            self.confirm(title: self.tr("Удалить плагин «", "Remove plugin “") + (self.installation(id)?.manifest.name ?? "") + self.tr("»?", "”?"), text: self.tr("Код и данные этого плагина для всех аккаунтов на устройстве будут удалены. Это действие нельзя отменить.", "This plugin's code and data for every account on this device will be removed. This cannot be undone."), destructive: true) { [weak self] in
                guard let self else { return }
                self.pendingRemoval = self.installation(id)
                self.busy = true
                self.refresh()
                self.manager.remove(id: id) { [weak self] result in
                    guard let self else { return }
                    self.busy = false
                    self.pendingRemoval = nil
                    switch result {
                    case .success: self.returnToListAfterRemoval()
                    case .failure: self.complete(result)
                    }
                }
            }
        } else if key.hasPrefix("reset:") {
            let id = String(key.dropFirst(6))
            self.confirm(title: self.tr("Сбросить данные плагина?", "Reset plugin data?"), text: self.tr("Настройки и локальные данные плагина для текущего аккаунта будут удалены. Плагин будет остановлен.", "The plugin's settings and local data for this account will be removed. The plugin will stop."), destructive: true) { [weak self] in
                self?.manager.resetData(id: id) { [weak self] result in self?.complete(result) }
            }
        } else if key.hasPrefix("rollback:") {
            let id = String(key.dropFirst(9))
            self.confirm(title: self.tr("Вернуться к предыдущей версии?", "Restore previous version?"), text: self.tr("Плагин будет остановлен. Проверьте разрешения перед повторным включением.", "The plugin will stop. Review permissions before enabling it again."), destructive: false) { [weak self] in
                self?.manager.rollback(id: id) { [weak self] result in self?.complete(result) }
            }
        } else if key.hasPrefix("publisher:") {
            let id = String(key.dropFirst(10))
            guard let identity = self.manager.publisherIdentity(id: id), identity.hasPrefix("ed25519:") else { return }
            let revoked = self.installation(id)?.trust != "revoked"
            self.confirm(title: revoked ? self.tr("Заблокировать издателя?", "Block publisher?") : self.tr("Разблокировать издателя?", "Unblock publisher?"), text: self.tr("Это изменит доверие ко всем плагинам этого ключа на устройстве. Блокировка немедленно остановит их.", "This changes trust for every plugin signed by this key on this device. Blocking stops them immediately."), destructive: revoked) { [weak self] in
                self?.manager.setPublisherRevoked(identity, revoked: revoked) { [weak self] result in self?.complete(result) }
            }
        } else if key.hasPrefix("command:"), let id = self.settingsInstallationId {
            self.bindNativeHost()
            self.manager.runCommand(installationId: id, commandId: String(key.dropFirst(8)), input: .null) { [weak self] result in self?.complete(result) }
        } else if key.hasPrefix("enum:"), case let .settings(id) = self.mode, let item = self.installation(id) {
            let setting = String(key.dropFirst(5))
            guard case let .array(choices)? = item.manifest.settingsSchema?.objectValue?["properties"]?.objectValue?[setting]?.objectValue?["enum"], choices.count <= 32 else { return }
            let actions = choices.map { choice in
                TextAlertAction(type: .genericAction, title: self.settingText(choice), action: { [weak self] in
                    var values = item.settings
                    values[setting] = choice
                    self?.manager.updateSettings(id: id, values: values) { [weak self] result in self?.complete(result) }
                })
            } + [TextAlertAction(type: .defaultAction, title: self.tr("Отмена", "Cancel"), action: {})]
            self.controller?.present(textAlertController(context: self.context, title: setting, text: "", actions: actions), in: .window(.root))
        }
    }

    func toggle(_ key: String, _ value: Bool) {
        guard !self.busy else { return }
        if key.hasPrefix("render:"), case let .rendered(state) = self.mode, let node = state.node(String(key.dropFirst(7))), node.type == "toggle" { state.invoke(node, value: .bool(value)); self.refresh(); return }
        if key == "global" { self.manager.setGloballyEnabled(value); return }
        if key.hasPrefix("enabled:") {
            let id = String(key.dropFirst(8))
            guard self.manager.globallyEnabled, let item = self.installation(id) else { self.refresh(); return }
            self.busy = true
            self.refresh()
            self.manager.setEnabled(id: id, enabled: value, reviewedDigest: item.digest) { [weak self] result in
                self?.busy = false
                self?.complete(result)
            }
        } else if key.hasPrefix("grant:"), case let .permissions(id) = self.mode, let item = self.installation(id), let index = Int(key.dropFirst(6)) {
            let requested = item.manifest.permissions + item.manifest.optionalPermissions
            guard requested.indices.contains(index) else { return }
            var grants = item.grants.filter { $0 != requested[index] }
            if value { grants.append(requested[index]) }
            self.manager.setGrants(id: id, permissions: grants) { [weak self] result in
                self?.complete(result)
            }
        } else if key.hasPrefix("setting:"), case let .settings(id) = self.mode, let item = self.installation(id) {
            var values = item.settings
            values[String(key.dropFirst(8))] = .bool(value)
            self.manager.updateSettings(id: id, values: values) { [weak self] result in self?.complete(result) }
        }
    }

    func input(_ key: String, _ value: String) {
        if key.hasPrefix("render:"), case let .rendered(state) = self.mode, let node = state.node(String(key.dropFirst(7))), node.type == "input" || node.type == "multiline" { state.invoke(node, value: .string(String(value.prefix(4096)))); return }
        if key == "search" { self.query = String(value.prefix(128)); self.refresh(); return }
        guard key.hasPrefix("setting:"), case let .settings(id) = self.mode, let item = self.installation(id) else { return }
        let setting = String(key.dropFirst(8))
        let schema = item.manifest.settingsSchema?.objectValue?["properties"]?.objectValue?[setting]?.objectValue
        var values = item.settings
        switch schema?["type"]?.stringValue {
        case "number", "integer":
            guard let number = Double(value), number.isFinite else { return }
            if schema?["type"]?.stringValue == "integer" && number.rounded() != number { return }
            values[setting] = .number(number)
        default: values[setting] = .string(String(value.prefix(4096)))
        }
        self.manager.updateSettings(id: id, values: values) { [weak self] result in self?.complete(result) }
    }

    func number(_ key: String, _ value: Double) {
        guard value.isFinite else { return }
        if key.hasPrefix("render:"), case let .rendered(state) = self.mode, let node = state.node(String(key.dropFirst(7))), node.type == "slider" || node.type == "stepper", value >= node.minimum, value <= node.maximum {
            state.invoke(node, value: .number(value))
            self.refresh()
        } else if key.hasPrefix("setting:"), case let .settings(id) = self.mode, let item = self.installation(id) {
            var values = item.settings
            values[String(key.dropFirst(8))] = .number(value)
            self.manager.updateSettings(id: id, values: values) { [weak self] result in self?.complete(result) }
        }
    }

    private func returnToListAfterRemoval() {
        let notice = self.tr("Плагин удалён", "Plugin removed")
        if let navigation = self.controller?.navigationController as? NavigationController {
            for (index, candidate) in navigation.viewControllers.enumerated().reversed() {
                guard let candidate = candidate as? ViewController, let page = dgPluginPages.object(forKey: candidate), case .list = page.mode else { continue }
                page.notice = notice
                page.refresh()
                navigation.setViewControllers(Array(navigation.viewControllers.prefix(index + 1)), animated: true)
                return
            }
        }
        self.mode = .list
        self.notice = notice
        self.refresh()
    }

    private var settingsInstallationId: String? {
        switch self.mode {
        case let .settings(id), let .details(id): return id
        default: return nil
        }
    }

    private func share(_ id: String) {
        self.busy = true
        self.refresh()
        self.manager.exportPackage(id: id) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .failure(error): self.busy = false; self.showError(error); self.refresh()
            case let .success(package):
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("donutgram-plugin-" + UUID().uuidString, isDirectory: true)
                    do {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        let url = directory.appendingPathComponent(package.fileName)
                        try package.data.write(to: url, options: .atomic)
                        DispatchQueue.main.async { [weak self] in
                            self?.busy = false
                            self?.refresh()
                            guard let controller = self?.controller, controller.isNodeLoaded, controller.view.window != nil, controller.presentedViewController == nil else { try? FileManager.default.removeItem(at: directory); return }
                            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
                            activity.popoverPresentationController?.sourceView = controller.view
                            activity.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.maxY - 1, width: 1, height: 1)
                            activity.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: directory) }
                            controller.present(activity, animated: true)
                        }
                    } catch {
                        try? FileManager.default.removeItem(at: directory)
                        DispatchQueue.main.async { [weak self] in
                            self?.busy = false
                            self?.showError(DGPluginError(code: "storage_error", message: "unable to prepare the plugin file"))
                            self?.refresh()
                        }
                    }
                }
            }
        }
    }

    private func complete(_ result: Result<Void, DGPluginError>) {
        if case let .failure(error) = result, error.code != "cancelled" { self.showError(error) }
        self.refresh()
    }

    private func showError(_ error: DGPluginError) {
        guard let controller = self.controller else { return }
        controller.present(textAlertController(context: self.context, title: self.tr("Не удалось", "Unable to complete"), text: dgPluginErrorDescription(error, russian: self.russian), actions: [TextAlertAction(type: .defaultAction, title: self.tr("Закрыть", "Close"), action: {})]), in: .window(.root))
    }

    private func confirm(title: String, text: String, destructive: Bool, action: @escaping () -> Void) {
        self.controller?.present(textAlertController(context: self.context, title: title, text: text, actions: [TextAlertAction(type: .genericAction, title: self.tr("Отмена", "Cancel"), action: {}), TextAlertAction(type: destructive ? .destructiveAction : .defaultAction, title: self.tr("Подтвердить", "Confirm"), action: action)]), in: .window(.root))
    }

    private func push(_ mode: DGPluginPageMode) {
        (self.controller?.navigationController as? NavigationController)?.pushViewController(dgMakePluginPage(context: self.context, mode: mode))
    }
}

private let dgPluginPages = NSMapTable<ViewController, DGPluginPage>.weakToWeakObjects()

private func dgMakePluginPage(context: AccountContext, mode: DGPluginPageMode) -> ItemListController {
    let page = DGPluginPage(context: context, mode: mode)
    return dgMakePluginPage(page: page)
}

private func dgMakePluginPage(page: DGPluginPage) -> ItemListController {
    let context = page.context
    dgBindPluginAccount(context: context)
    // On the main queue: the state reads the page and its controller, and the theme can change on another queue.
    let signal = combineLatest(context.sharedContext.presentationData, page.revision.get())
    |> deliverOnMainQueue
    |> map { [page] presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let data = ItemListPresentationData(presentationData)
        let close = ItemListNavigationButton(content: .text(page.tr("Закрыть", "Close")), style: .regular, enabled: !page.busy, action: { [weak page] in
            guard let controller = page?.controller else { return }
            if case let .rendered(state)? = page?.mode { state.close() }
            if let navigation = controller.navigationController as? NavigationController { let _ = navigation.popViewController(animated: true) }
            else { controller.dismiss() }
        })
        // Inside a navigation stack the bar already has a button of its own: back for a pushed page, a cross for a
        // sheet. «Закрыть» is only for a page presented on its own, such as a plugin's page over the chat, where
        // nothing else leads out. A page joins its stack before it first builds this state.
        let standalone = page.controller?.navigationController == nil
        let state = ItemListControllerState(presentationData: data, title: .text(page.title), leftNavigationButton: nil, rightNavigationButton: standalone ? close : nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: data, entries: page.rows(), style: .blocks, animateChanges: false), page))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.alwaysSynchronous = true
    page.controller = controller
    controller.didAppear = { [weak page] _ in page?.bindNativeHost() }
    dgPluginPages.setObject(page, forKey: controller)
    controller.didDisappear = { [weak page, weak controller] _ in
        guard let page, let controller, case let .rendered(state) = page.mode else { return }
        if let navigation = controller.navigationController, navigation.viewControllers.contains(where: { $0 === controller }) { return }
        state.close()
    }
    return controller
}

public func dgPluginsController(context: AccountContext) -> ViewController {
    return dgMakePluginPage(context: context, mode: .list)
}

public func dgPluginInstallController(context: AccountContext, package: DGVerifiedPluginPackage) -> ViewController {
    return DGPluginInstallController(context: context, package: package)
}

func dgInstalledPluginSettingsController(context: AccountContext, id: String) -> ViewController {
    return dgMakePluginPage(context: context, mode: .settings(id))
}

public func dgPluginRenderedController(context: AccountContext, page: DGPluginJSON, pluginName: String, validity: @escaping () -> Bool, onCallback: @escaping (String, DGPluginJSON) -> Void, assetProvider: @escaping (String) -> Data? = { _ in nil }, onClose: (() -> Void)? = nil) throws -> ViewController {
    guard validity() else { throw DGPluginError(code: "cancelled", message: "plugin page is no longer current") }
    let envelope = dgPluginNativePageEnvelope(page)
    let state = try DGPluginRenderedState(page: envelope.page, pluginName: pluginName, validity: validity, assetProvider: assetProvider, onClose: onClose, callback: onCallback)
    let session = DGPluginPage(context: context, mode: .rendered(state))
    session.renderedAccent = dgPluginAccent(envelope.accent)
    session.renderedImages = try dgPluginResolveImages(state)
    return dgMakePluginPage(page: session)
}

public func dgUpdatePluginRenderedController(_ controller: ViewController, page: DGPluginJSON, pluginName: String, validity: @escaping () -> Bool, onCallback: @escaping (String, DGPluginJSON) -> Void, assetProvider: @escaping (String) -> Data? = { _ in nil }, onClose: (() -> Void)? = nil) throws -> Bool {
    guard validity(), let session = dgPluginPages.object(forKey: controller), case let .rendered(oldState) = session.mode else { return false }
    let envelope = dgPluginNativePageEnvelope(page)
    let state = try DGPluginRenderedState(page: envelope.page, pluginName: pluginName, validity: validity, assetProvider: assetProvider, onClose: onClose, callback: onCallback)
    let images = try dgPluginResolveImages(state)
    guard validity() else { return false }
    oldState.supersede()
    session.mode = .rendered(state)
    session.renderedImages = images
    session.renderedAccent = dgPluginAccent(envelope.accent)
    session.refresh()
    return true
}

private func dgPluginAccent(_ name: String?) -> UIColor? {
    switch name { case "blue": return .systemBlue; case "green": return .systemGreen; case "purple": return .systemPurple; case "orange": return .systemOrange; default: return nil }
}

private func dgPluginResolveImages(_ state: DGPluginRenderedState) throws -> [String: UIImage] {
    var images: [String: UIImage] = [:]
    func visit(_ nodes: [DGPluginRenderNode]) throws {
        for node in nodes {
            if let handle = node.asset {
                if images[handle] != nil { continue }
                guard images.count < 8 else { throw DGPluginError(code: "quota_exceeded", message: "too many local images") }
                guard state.validity(), let data = state.assetProvider(handle), let image = dgPluginRasterImage(data: data, maximumPixelSize: 512) else { throw DGPluginError(code: "stale_handle", message: "local image asset is unavailable") }
                images[handle] = image
            }
            try visit(node.children)
        }
    }
    try visit(state.nodes)
    return images
}

private var dgPluginAccountBindings: [String: Disposable] = [:]

public func dgBindPluginAccount(context: AccountContext) {
    precondition(Thread.isMainThread)
    let key = String(context.account.id.int64)
    guard dgPluginAccountBindings[key] == nil else { return }
    let manager = DGPluginManager.shared(accountKey: key)
    let accountId = context.account.id
    manager.setPowerSaving(context.sharedContext.energyUsageSettings.enhancedPowerSaving)
    dgPluginAccountBindings[key] = (combineLatest(context.sharedContext.activeAccountContexts, context.sharedContext.applicationBindings.applicationInForeground, context.sharedContext.presentationData)
    |> deliverOnMainQueue).start(next: { accounts, foreground, presentation in
        manager.setAccountActive(accounts.primary?.account.id == accountId)
        manager.setForegroundActive(foreground)
        manager.updateEnvironment(locale: presentation.strings.primaryComponent.languageCode, appearance: presentation.theme.overallDarkAppearance ? "dark" : "light")
    })
}

private var dgPluginDocumentImports: [String: DGPluginDocumentOperation<DGVerifiedPluginPackage>] = [:]

public func dgOpenPluginDocument(context: AccountContext, file: FileMediaReference, present: @escaping (ViewController) -> Void, presentOverlay: @escaping (ViewController) -> Void) -> Bool {
    let fileName = file.media.fileName ?? ""
    guard fileName.lowercased().hasSuffix(".donut.js") || fileName.lowercased().hasSuffix(".dgplugin") else { return false }
    precondition(Thread.isMainThread)
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let russian = presentationData.strings.primaryComponent.languageCode.hasPrefix("ru")
    let showError: (String) -> Void = { text in
        presentOverlay(textAlertController(context: context, title: russian ? "Не удалось открыть плагин" : "Unable to open plugin", text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]))
    }
    let key = String(context.account.id.int64)
    dgPluginDocumentImports[key]?.finish(nil)
    let limit = 8 * 1024 * 1024
    if let size = file.media.size, size > Int64(limit) {
        showError(russian ? "Файл плагина больше 8 МБ." : "The plugin file is larger than 8 MB.")
        return true
    }
    var cancel: (() -> Void)?
    let overlay = OverlayStatusController(style: presentationData.theme.overallDarkAppearance ? .dark : .light, type: .loading(cancelled: { cancel?() }))
    let operation = DGPluginDocumentOperation<DGVerifiedPluginPackage> { [weak overlay] result in
        dgPluginDocumentImports.removeValue(forKey: key)
        overlay?.dismiss()
        guard let result else { return }
        switch result {
        case let .success(package):
            present(dgPluginInstallController(context: context, package: package))
        case let .failure(error):
            showError(error.code == "validation_timeout" ? (russian ? "Не удалось подготовить плагин за 30 секунд. Откройте файл ещё раз." : "The plugin could not be prepared within 30 seconds. Open the file again.") : dgPluginErrorDescription(error, russian: russian))
        }
    }
    cancel = { [weak operation] in operation?.finish(nil) }
    dgPluginDocumentImports[key] = operation
    presentOverlay(overlay)
    let resource = file.media.resource
    let source = Signal<EngineMediaResource.ResourceData?, NoError> { subscriber in
        let read = (context.engine.resources.data(resource: EngineMediaResource(resource))
        |> filter { $0.isComplete }
        |> take(1)).start(next: { data in subscriber.putNext(data); subscriber.putCompletion() })
        let fetch = context.engine.resources.fetch(reference: file.abstract.resourceReference(resource), userLocation: .other, userContentType: .file).start(error: { _ in subscriber.putNext(nil); subscriber.putCompletion() })
        return ActionDisposable { read.dispose(); fetch.dispose() }
    }
    operation.disposable.set((dgPluginValidateDocument(source: source, validate: { resourceData -> DGVerifiedPluginPackage in
        guard let resourceData else { throw DGPluginError(code: "download_failed", message: "unable to download plugin document") }
        let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: resourceData.path))
        defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw DGPluginError(code: "package_too_large", message: "plugin document exceeds 8 mib") }
        return try DGPluginInstaller.preview(data: data, fileName: fileName)
    })
    |> deliverOnMainQueue).start(next: { [weak operation] result in operation?.finish(result) }))
    return true
}

private let dgPluginDocumentIconCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 64
    cache.totalCostLimit = 4 * 1024 * 1024
    return cache
}()

private let dgPluginDocumentIconQueue = Queue(name: "donutgram.plugin.document-icon", qos: .utility)

public func dgPluginDocumentIcon(context: AccountContext, file: TelegramMediaFile) -> Signal<UIImage?, NoError> {
    let name = file.fileName ?? ""
    guard name.lowercased().hasSuffix(".donut.js") || name.lowercased().hasSuffix(".dgplugin") else { return .single(nil) }
    return context.engine.resources.data(resource: EngineMediaResource(file.resource))
    |> filter { $0.isComplete }
    |> take(1)
    |> deliverOn(dgPluginDocumentIconQueue)
    |> map { resource -> UIImage? in
        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: resource.path))
            defer { try? handle.close() }
            let bytes = try handle.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
            guard bytes.count <= 8 * 1024 * 1024 else { return nil }
            let digest = DGPluginInstaller.digest(bytes)
            if let image = dgPluginDocumentIconCache.object(forKey: digest as NSString) { return image }
            let package = try DGPluginInstaller.preview(data: bytes, fileName: name)
            let image = dgPluginIcon(data: package.iconData, id: package.manifest.id, name: package.manifest.name, size: 44)
            let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 44 * 44 * 4
            dgPluginDocumentIconCache.setObject(image, forKey: digest as NSString, cost: cost)
            return image
        } catch { return nil }
    }
}

private func dgPluginRasterImage(data: Data, maximumPixelSize: Int) -> UIImage? {
    if data.count <= 262144, let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
       let type = CGImageSourceGetType(source) as String?, ["public.png", "public.jpeg"].contains(type),
       let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
       let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
       width > 0, height > 0, width <= 1024, height <= 1024,
       let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
        return UIImage(cgImage: image)
    }
    return nil
}

public func dgPluginIcon(data: Data?, id: String, name: String, size: CGFloat = 40) -> UIImage {
    let dimension = min(96, max(20, size))
    if let data, let image = dgPluginRasterImage(data: data, maximumPixelSize: Int(dimension * 3)), let bitmap = image.cgImage {
        return UIGraphicsImageRenderer(size: CGSize(width: dimension, height: dimension)).image { _ in
            let width = CGFloat(bitmap.width)
            let height = CGFloat(bitmap.height)
            let scale = min(dimension / width, dimension / height)
            image.draw(in: CGRect(x: (dimension - width * scale) / 2, y: (dimension - height * scale) / 2, width: width * scale, height: height * scale))
        }
    }
    var hash: UInt32 = 2166136261
    for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: dimension, height: dimension))
    return renderer.image { _ in
        UIColor(hue: CGFloat(hash % 360) / 360, saturation: 0.45, brightness: 0.65, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: dimension, height: dimension), cornerRadius: dimension * 0.225).fill()
        if #available(iOS 13.0, *), let symbol = UIImage(systemName: "puzzlepiece.extension.fill") ?? UIImage(systemName: "square.grid.2x2.fill") {
            let inset = dimension * 0.23
            symbol.withTintColor(.white, renderingMode: .alwaysOriginal).draw(in: CGRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2))
        }
    }
}
