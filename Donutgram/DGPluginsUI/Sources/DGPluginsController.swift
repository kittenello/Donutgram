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
import DGPluginModel
import DGPluginInstaller
import DGPluginHost

private struct DGPluginRow: ItemListNodeEntry {
    enum Kind: Equatable { case header, text, disclosure, toggle, input, action, destructive }
    let stableId: Int32
    let section: ItemListSectionId
    let kind: Kind
    let key: String
    let title: String
    var detail: String = ""
    var value: Bool = false
    var enabled: Bool = true
    var iconKey: String = ""

    static func < (lhs: DGPluginRow, rhs: DGPluginRow) -> Bool { return lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let page = arguments as! DGPluginPage
        switch self.kind {
        case .header:
            return ItemListSectionHeaderItem(presentationData: presentationData, text: self.title, sectionId: self.section)
        case .text:
            return ItemListTextItem(presentationData: presentationData, text: .plain(self.title), sectionId: self.section)
        case .disclosure:
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: self.iconKey.isEmpty ? nil : page.icon(self.iconKey), title: self.title, label: self.detail, labelStyle: .multilineDetailText, sectionId: self.section, style: .blocks, action: { page.action(self.key) })
        case .toggle:
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: self.title, value: self.value, enableInteractiveChanges: self.enabled, enabled: self.enabled, maximumNumberOfLines: 0, sectionId: self.section, style: .blocks, updated: { page.toggle(self.key, $0) })
        case .input:
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: self.key == "search" ? "" : self.title), text: self.detail, placeholder: self.title, type: .regular(capitalization: false, autocorrection: false), clearType: .always, sectionId: self.section, textUpdated: { page.input(self.key, $0) }, action: {})
        case .action, .destructive:
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: self.title, kind: self.kind == .destructive ? .destructive : .generic, alignment: .natural, sectionId: self.section, style: .blocks, action: { if self.enabled { page.action(self.key) } })
        }
    }
}

private enum DGPluginPageMode {
    case list
    case loading
    case install(DGVerifiedPluginPackage)
    case details(String)
    case permissions(String)
    case settings(String)
    case failure(String)
    case rendered(DGPluginRenderedState)
}

private struct DGPluginRenderChoice {
    let title: String
    let value: DGPluginJSON
}

private struct DGPluginRenderNode {
    let type: String
    let id: String
    let title: String
    let text: String
    let value: DGPluginJSON
    let callbackId: String?
    let options: [DGPluginRenderChoice]
    let children: [DGPluginRenderNode]
}

private final class DGPluginRenderedState {
    let title: String
    let pluginName: String
    let nodes: [DGPluginRenderNode]
    let validity: () -> Bool
    let callback: (String, DGPluginJSON) -> Void
    var values: [String: DGPluginJSON] = [:]

    init(page: DGPluginJSON, pluginName: String, validity: @escaping () -> Bool, callback: @escaping (String, DGPluginJSON) -> Void) throws {
        guard try JSONEncoder().encode(page).count <= 65536, let object = page.objectValue, Set(object.keys).isSubset(of: ["id", "title", "nodes"]), let id = object["id"]?.stringValue, Self.validId(id), let title = object["title"]?.stringValue, !title.isEmpty, Self.validText(title, multiline: false), title.utf16.count <= 200, case let .array(nodes)? = object["nodes"] else { throw DGPluginError(code: "invalid_argument", message: "invalid declarative page") }
        var ids = Set<String>()
        var count = 0
        self.nodes = try Self.parse(nodes, depth: 0, count: &count, ids: &ids)
        self.title = title
        self.pluginName = pluginName
        self.validity = validity
        self.callback = callback
    }

    private static func validId(_ id: String) -> Bool {
        return id.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,63}$", options: .regularExpression) != nil
    }

    private static func validText(_ text: String, multiline: Bool) -> Bool {
        return !text.unicodeScalars.contains { scalar in
            if multiline && [9, 10, 13].contains(scalar.value) { return false }
            return CharacterSet.controlCharacters.contains(scalar) || (0x202a ... 0x202e).contains(scalar.value) || (0x2066 ... 0x2069).contains(scalar.value)
        }
    }

    private static func parse(_ nodes: [DGPluginJSON], depth: Int, count: inout Int, ids: inout Set<String>) throws -> [DGPluginRenderNode] {
        guard depth <= 6, nodes.count <= 128 else { throw DGPluginError(code: "quota_exceeded", message: "page nesting or node limit exceeded") }
        return try nodes.map { value in
            count += 1
            guard count <= 128, let node = value.objectValue, Set(node.keys).isSubset(of: ["type", "id", "title", "text", "value", "callbackId", "children", "options"]), let type = node["type"]?.stringValue, let id = node["id"]?.stringValue, Self.validId(id), ids.insert(id).inserted else { throw DGPluginError(code: "invalid_argument", message: "invalid or duplicate page node") }
            guard ["section", "text", "list", "button", "toggle", "input", "select"].contains(type) else { throw DGPluginError(code: "feature_unavailable", message: "unsupported declarative node: " + type) }
            let title = node["title"]?.stringValue ?? ""
            let text = node["text"]?.stringValue ?? ""
            guard (node["title"] == nil || node["title"]?.stringValue != nil), (node["text"] == nil || node["text"]?.stringValue != nil), title.utf16.count <= 200, text.utf16.count <= 4096, Self.validText(title, multiline: false), Self.validText(text, multiline: true) else { throw DGPluginError(code: "invalid_argument", message: "invalid page text") }
            let callbackId = node["callbackId"]?.stringValue
            guard node["callbackId"] == nil || callbackId != nil, node["options"] == nil || type == "select" else { throw DGPluginError(code: "invalid_argument", message: "invalid node options or callback") }
            if ["button", "toggle", "input", "select"].contains(type) {
                guard let callbackId, Self.validId(callbackId) else { throw DGPluginError(code: "invalid_argument", message: "interactive nodes require callbackId") }
            } else if callbackId != nil { throw DGPluginError(code: "invalid_argument", message: "noninteractive nodes cannot receive callbacks") }
            let inputValue = node["value"] ?? .null
            if type == "toggle", case .bool = inputValue {} else if type == "toggle" { throw DGPluginError(code: "invalid_argument", message: "toggle value must be boolean") }
            if type == "input" { guard let string = inputValue.stringValue, string.utf16.count <= 4096 else { throw DGPluginError(code: "invalid_argument", message: "input value must be bounded text") } }
            var options: [DGPluginRenderChoice] = []
            if type == "select" {
                guard case let .array(choices)? = node["options"], !choices.isEmpty, choices.count <= 32 else { throw DGPluginError(code: "invalid_argument", message: "select requires bounded options") }
                for option in choices {
                    guard let choice = option.objectValue, Set(choice.keys) == ["title", "value"], let title = choice["title"]?.stringValue, !title.isEmpty, title.utf16.count <= 200, Self.validText(title, multiline: false), let value = choice["value"] else { throw DGPluginError(code: "invalid_argument", message: "invalid select option") }
                    switch value {
                    case let .string(string): guard string.utf16.count <= 4096 else { throw DGPluginError(code: "quota_exceeded", message: "invalid select option value") }
                    case .bool, .number, .null: break
                    default: throw DGPluginError(code: "invalid_argument", message: "select options must be scalar values")
                    }
                    options.append(DGPluginRenderChoice(title: title, value: value))
                }
                guard options.contains(where: { $0.value == inputValue }) else { throw DGPluginError(code: "invalid_argument", message: "select value is not an option") }
            }
            var children: [DGPluginRenderNode] = []
            if let childValue = node["children"] {
                guard ["section", "list"].contains(type), case let .array(childNodes) = childValue else { throw DGPluginError(code: "invalid_argument", message: "only containers may have children") }
                children = try Self.parse(childNodes, depth: depth + 1, count: &count, ids: &ids)
            }
            return DGPluginRenderNode(type: type, id: id, title: title, text: text, value: inputValue, callbackId: callbackId, options: options, children: children)
        }
    }

    func node(_ id: String) -> DGPluginRenderNode? {
        func find(_ nodes: [DGPluginRenderNode]) -> DGPluginRenderNode? {
            for node in nodes { if node.id == id { return node }; if let child = find(node.children) { return child } }
            return nil
        }
        return find(self.nodes)
    }

    func invoke(_ node: DGPluginRenderNode, value: DGPluginJSON) {
        guard self.validity(), let callbackId = node.callbackId else { return }
        self.values[node.id] = value
        self.callback(callbackId, value)
    }
}

private final class DGPluginPage {
    let context: AccountContext
    let manager: DGPluginManager
    let revision = ValuePromise<Int>(0, ignoreRepeated: false)
    weak var controller: ItemListController?
    var mode: DGPluginPageMode
    var query = ""
    var busy = false
    var enableAfterInstall = false
    var observer: UUID?
    var resourceDisposable: Disposable?
    private var sequence = 0

    init(context: AccountContext, mode: DGPluginPageMode) {
        self.context = context
        self.manager = DGPluginManager.shared(accountKey: String(context.account.id.int64))
        self.mode = mode
        self.observer = self.manager.observe { [weak self] in self?.refresh() }
    }

    deinit {
        if let observer = self.observer { self.manager.removeObserver(observer) }
        self.resourceDisposable?.dispose()
    }

    func tr(_ ru: String, _ en: String) -> String {
        return self.context.sharedContext.currentPresentationData.with { $0 }.strings.primaryComponent.languageCode.hasPrefix("ru") ? ru : en
    }

    func refresh() {
        self.sequence += 1
        self.revision.set(self.sequence)
    }

    func installation(_ id: String) -> DGPluginInstallation? {
        return self.manager.installations.first(where: { $0.id == id })
    }

    var title: String {
        switch self.mode {
        case .list: return self.tr("плагины", "plugins")
        case .permissions: return self.tr("разрешения", "permissions")
        case .settings: return self.tr("настройки плагина", "plugin settings")
        case .install: return self.tr("установка плагина", "install plugin")
        case let .details(id): return self.installation(id)?.manifest.name ?? self.tr("плагин удалён", "plugin removed")
        case .loading: return self.tr("проверка файла", "checking file")
        case .failure: return self.tr("файл не установлен", "file not installed")
        case let .rendered(state): return state.title
        }
    }

    func rows() -> [DGPluginRow] {
        var rows: [DGPluginRow] = []
        func add(_ section: Int32, _ kind: DGPluginRow.Kind, _ key: String, _ title: String, detail: String = "", value: Bool = false, enabled: Bool = true, icon: String = "") {
            rows.append(DGPluginRow(stableId: Int32(rows.count), section: section, kind: kind, key: key, title: title, detail: detail, value: value, enabled: enabled && !self.busy, iconKey: icon))
        }
        switch self.mode {
        case .list:
            add(0, .toggle, "global", self.tr("разрешить выполнение плагинов", "allow plugins to run"), value: self.manager.globallyEnabled)
            add(0, .text, "", self.tr("выключение немедленно останавливает все плагины и их задачи.", "turning this off immediately stops all plugins and their tasks."))
            add(1, .input, "search", self.tr("поиск", "search"), detail: self.query)
            add(1, .header, "", self.tr("установленные", "installed"))
            let matches = self.manager.installations.filter { self.query.isEmpty || ($0.manifest.name + " " + $0.manifest.id + " " + ($0.manifest.author?.name ?? "")).localizedCaseInsensitiveContains(self.query) }
            if matches.isEmpty {
                add(1, .text, "", self.query.isEmpty ? self.tr("плагинов пока нет. откройте файл .donut.js или .dgplugin в сообщении telegram. просмотр файла не запускает код.", "no plugins yet. open a .donut.js or .dgplugin document in a telegram message. previewing never runs code.") : self.tr("ничего не найдено", "nothing found"))
            }
            for (index, item) in matches.enumerated() {
                let section = Int32(index + 2)
                add(section, .disclosure, "details:" + item.id, item.manifest.name, detail: (item.manifest.author?.name ?? self.tr("автор не указан", "author not specified")) + " · " + item.manifest.version + " · " + self.stateText(item), icon: item.id)
                add(section, .toggle, "enabled:" + item.id, self.tr("включён", "enabled"), value: item.enabled)
            }
        case .loading:
            add(0, .text, "", self.tr("проверяем неизменяемую копию вложения без запуска javascript…", "checking an immutable attachment copy without running javascript…"))
        case let .failure(message):
            add(0, .text, "", message)
        case let .install(package):
            self.appendCard(manifest: package.manifest, trust: package.trust, digest: package.digest, iconKey: "preview", add: add)
            if let old = self.manager.installations.first(where: { $0.manifest.id == package.manifest.id }) {
                add(2, .header, "", self.tr("обновление", "update review"))
                add(2, .text, "", old.manifest.version + " → " + package.manifest.version)
                if old.manifest.profile != package.manifest.profile { add(2, .text, "", self.tr("изменён профиль: ", "profile changed: ") + old.manifest.profile + " → " + package.manifest.profile) }
                let previous = Set(old.manifest.permissions + old.manifest.optionalPermissions)
                let added = (package.manifest.permissions + package.manifest.optionalPermissions).filter { !previous.contains($0) }
                add(2, .text, "", added.isEmpty ? self.tr("новых разрешений нет. после обновления проверьте разрешения и включите плагин самостоятельно.", "no new permissions. review permissions and enable the plugin after updating.") : self.tr("новые разрешения:\n", "new permissions:\n") + added.map(self.permissionText).joined(separator: "\n\n"))
                add(4, .action, "install", self.busy ? self.tr("обновляем…", "updating…") : self.tr("подтвердить обновление", "confirm update"))
            } else {
                add(4, .action, "install", self.busy ? self.tr("устанавливаем…", "installing…") : self.tr("установить выключенным", "install disabled"))
            }
            add(4, .toggle, "afterInstall", self.tr("включить после установки", "enable after installation"), value: self.enableAfterInstall)
            add(4, .text, "", self.tr("установка не выдаёт разрешения и не запускает код. подпись подтверждает происхождение, а не безопасность кода.", "installing grants no permissions and runs no code. a signature proves origin, not code safety."))
        case let .details(id):
            guard let item = self.installation(id) else { add(0, .text, "", self.tr("этот плагин удалён.", "this plugin has been removed.")); break }
            self.appendCard(manifest: item.manifest, trust: item.trust, digest: item.digest, iconKey: id, add: add)
            add(4, .toggle, "enabled:" + id, self.tr("включён", "enabled"), value: item.enabled)
            add(4, .text, "", self.stateText(item))
            if let error = item.lastError { add(4, .text, "", error) }
            add(5, .disclosure, "permissions:" + id, self.tr("разрешения", "permissions"), detail: "\(item.grants.count)")
            add(5, .disclosure, "settings:" + id, self.tr("настройки", "settings"))
            add(5, .action, "reset:" + id, self.tr("сбросить настройки и данные", "reset settings and data"))
            for command in self.manager.commands.filter({ $0.installationId == id && $0.placement == "settings" }) {
                add(6, .action, "command:" + command.id, command.title)
            }
            add(7, .text, "", self.tr("для обновления откройте новый файл плагина в сообщении telegram. автоматической загрузки кода нет.", "to update, open the new plugin document in a telegram message. code is never downloaded automatically."))
            add(8, .destructive, "remove:" + id, self.tr("удалить плагин", "remove plugin"))
        case let .permissions(id):
            guard let item = self.installation(id) else { break }
            add(0, .text, "", self.tr("каждое разрешение выдаётся отдельно. отзыв немедленно отменяет связанные действия. обязательные права нужны для включения.", "grant each permission separately. revoking immediately cancels related work. required permissions are needed to enable the plugin."))
            for (index, permission) in (item.manifest.permissions + item.manifest.optionalPermissions).enumerated() {
                let section = Int32(index + 1)
                add(section, .toggle, "grant:\(index)", self.permissionTitle(permission.capability), value: item.grants.contains(permission))
                let required = index < item.manifest.permissions.count
                add(section, .text, "", (required ? self.tr("обязательное\n", "required\n") : self.tr("необязательное\n", "optional\n")) + self.permissionText(permission))
            }
        case let .settings(id):
            guard let item = self.installation(id) else { break }
            let properties = item.manifest.settingsSchema?.objectValue?["properties"]?.objectValue ?? [:]
            if properties.isEmpty { add(0, .text, "", self.tr("у плагина нет настроек.", "this plugin has no settings.")) }
            for (index, key) in properties.keys.sorted().enumerated() {
                guard let schema = properties[key]?.objectValue else { continue }
                let title = schema["title"]?.stringValue ?? key
                let value = item.settings[key] ?? schema["default"] ?? .null
                let section = Int32(index)
                if case .array? = schema["enum"] {
                    add(section, .disclosure, "enum:" + key, title, detail: self.settingText(value))
                    continue
                }
                switch schema["type"]?.stringValue {
                case "boolean":
                    add(section, .toggle, "setting:" + key, title, value: value == .bool(true))
                case "string", "number", "integer":
                    add(section, .input, "setting:" + key, title, detail: self.settingText(value))
                default:
                    add(section, .text, "", title + ": " + self.tr("этот тип настройки пока недоступен", "this setting type is unavailable"))
                }
                if let description = schema["description"]?.stringValue { add(section, .text, "", description) }
            }
        case let .rendered(state):
            add(0, .text, "", self.tr("страница плагина: ", "plugin page: ") + state.pluginName)
            guard state.validity() else { add(0, .text, "", self.tr("плагин остановлен или доступ отозван. закройте эту страницу.", "the plugin stopped or permission was revoked. close this page.")); break }
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
                    case "button": add(section, .action, key, node.title)
                    case "toggle": add(section, .toggle, key, node.title, value: value == .bool(true))
                    case "input": add(section, .input, key, node.title, detail: self.settingText(value))
                    case "select": add(section, .disclosure, key, node.title, detail: node.options.first(where: { $0.value == value })?.title ?? self.settingText(value))
                    default: break
                    }
                }
            }
            append(state.nodes)
        }
        return rows
    }

    private func appendCard(manifest: DGPluginManifest, trust: String, digest: String, iconKey: String, add: (Int32, DGPluginRow.Kind, String, String, String, Bool, Bool, String) -> Void) {
        add(0, .disclosure, "", manifest.name, manifest.version, false, true, iconKey)
        add(0, .text, "", manifest.description, "", false, true, "")
        let author = manifest.author.map { $0.name + ($0.username.map { " (@\($0))" } ?? "") } ?? self.tr("не указан", "not specified")
        add(0, .text, "", self.tr("заявленный автор: ", "claimed author: ") + author + "\n" + manifest.id, "", false, true, "")
        add(1, .text, "", self.tr("доверие: ", "trust: ") + self.trustText(trust) + "\n" + self.tr("профиль: ", "profile: ") + manifest.profile + "\nsha256: " + digest, "", false, true, "")
        add(3, .header, "", self.tr("запрашиваемые разрешения", "requested permissions"), "", false, true, "")
        let permissions = manifest.permissions.map { self.tr("обязательное: ", "required: ") + self.permissionText($0) } + manifest.optionalPermissions.map { self.tr("необязательное: ", "optional: ") + self.permissionText($0) }
        add(3, .text, "", permissions.isEmpty ? self.tr("разрешения не запрошены", "no permissions requested") : permissions.joined(separator: "\n\n"), "", false, true, "")
        if let changelog = manifest.changelog, !changelog.isEmpty { add(3, .text, "", changelog, "", false, true, "") }
    }

    private func permissionText(_ permission: DGPluginPermission) -> String {
        return self.permissionTitle(permission.capability) + "\n" + permission.reason + "\n" + permission.capability + " · " + permission.scope + (permission.origins.isEmpty ? "" : "\n" + permission.origins.joined(separator: "\n"))
    }

    private func permissionTitle(_ capability: String) -> String {
        switch capability {
        case "ui.contribute": return self.tr("команды и панели", "commands and panels")
        case "ui.transform": return self.tr("локальное оформление экранов", "local screen appearance")
        case "theme.read": return self.tr("текущая тема", "current theme")
        case "theme.contribute": return self.tr("локальные цвета и оформление", "local colors and decorations")
        case "composer.read": return self.tr("текст открытого черновика", "text in the open draft")
        case "composer.transform": return self.tr("изменение открытого черновика", "change the open draft")
        case "messages.selection.read": return self.tr("выделенный вами текст", "text you select")
        case "messages.read": return self.tr("сообщения в выбранных чатах", "messages in selected chats")
        case "chats.metadata.read": return self.tr("названия выбранных чатов", "selected chat names")
        case "peers.read": return self.tr("данные выбранных контактов", "selected contact details")
        case "storage.local": return self.tr("собственные локальные данные", "own local data")
        case "network.public": return self.tr("публичные интернет-сервисы", "public internet services")
        case "translation.request": return self.tr("перевод выбранного текста", "translate selected text")
        case "navigation.open": return self.tr("открытие разрешённых экранов", "open allowed screens")
        case "notifications.local": return self.tr("локальные уведомления", "local notifications")
        case "files.userSelected": return self.tr("выбранный вами файл", "file you choose")
        case "messages.compose": return self.tr("подготовка сообщения", "prepare a message")
        case "messages.sendInteractive": return self.tr("отправка с вашим подтверждением", "send with your confirmation")
        default: return capability
        }
    }

    private func settingText(_ value: DGPluginJSON) -> String {
        switch value { case let .string(text): return text; case let .number(number): return String(number); case let .bool(value): return value ? self.tr("да", "yes") : self.tr("нет", "no"); default: return "" }
    }

    private func trustText(_ trust: String) -> String {
        switch trust {
        case "verified", "signatureVerified": return self.tr("подпись проверена", "signature verified")
        case "signatureMismatch": return self.tr("подпись не совпадает", "signature mismatch")
        case "revoked": return self.tr("источник отозван", "source revoked")
        case "modified": return self.tr("пакет изменён после проверки", "package modified after verification")
        default: return self.tr("из файла · автор не подтверждён", "from file · unverified author")
        }
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

    func icon(_ key: String) -> UIImage {
        let manifest: DGPluginManifest?
        let data: Data?
        if key == "preview", case let .install(package) = self.mode {
            manifest = package.manifest
            data = package.iconData
        } else {
            manifest = self.installation(key)?.manifest
            data = self.manager.iconData(id: key)
        }
        return dgPluginIcon(data: data, id: manifest?.id ?? key, name: manifest?.name ?? "dg")
    }

    func action(_ key: String) {
        guard !self.busy else { return }
        if key.hasPrefix("render:"), case let .rendered(state) = self.mode, let node = state.node(String(key.dropFirst(7))), state.validity() {
            if node.type == "select" {
                let actions = node.options.map { option in TextAlertAction(type: .genericAction, title: option.title, action: { [weak self, weak state] in state?.invoke(node, value: option.value); self?.refresh() }) } + [TextAlertAction(type: .defaultAction, title: self.tr("отмена", "cancel"), action: {})]
                self.controller?.present(textAlertController(context: self.context, title: node.title, text: "", actions: actions), in: .window(.root))
            } else { state.invoke(node, value: .null) }
            return
        }
        if key.hasPrefix("details:") { self.push(.details(String(key.dropFirst(8)))); return }
        if key.hasPrefix("permissions:") { self.push(.permissions(String(key.dropFirst(12)))); return }
        if key.hasPrefix("settings:") { self.push(.settings(String(key.dropFirst(9)))); return }
        if key == "install", case let .install(package) = self.mode {
            self.busy = true
            self.refresh()
            self.manager.install(package) { [weak self] result in
                guard let self else { return }
                self.busy = false
                switch result {
                case let .success(id):
                    self.mode = .details(id)
                    if self.enableAfterInstall {
                        if let item = self.installation(id), item.manifest.permissions.allSatisfy({ item.grants.contains($0) }) {
                            self.enableAfterInstall = false
                            self.manager.setEnabled(id: id, enabled: true) { [weak self] result in self?.complete(result) }
                        } else { self.mode = .permissions(id) }
                    }
                case let .failure(error): self.showError(error)
                }
                self.refresh()
            }
        } else if key.hasPrefix("remove:") {
            let id = String(key.dropFirst(7))
            self.confirm(title: self.tr("удалить плагин «", "remove plugin “") + (self.installation(id)?.manifest.name ?? "") + self.tr("»?", "”?"), text: self.tr("код и данные этого плагина для всех аккаунтов на устройстве будут удалены. это действие нельзя отменить.", "this plugin's code and data for every account on this device will be removed. this cannot be undone."), destructive: true) { [weak self] in
                guard let self else { return }
                self.manager.remove(id: id) { [weak self] result in self?.complete(result) }
            }
        } else if key.hasPrefix("reset:") {
            let id = String(key.dropFirst(6))
            self.confirm(title: self.tr("сбросить данные плагина?", "reset plugin data?"), text: self.tr("настройки и локальные данные плагина для текущего аккаунта будут удалены. плагин будет остановлен.", "the plugin's settings and local data for this account will be removed. the plugin will stop."), destructive: true) { [weak self] in
                self?.manager.resetData(id: id) { [weak self] result in self?.complete(result) }
            }
        } else if key.hasPrefix("command:"), case let .details(id) = self.mode {
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
            } + [TextAlertAction(type: .defaultAction, title: self.tr("отмена", "cancel"), action: {})]
            self.controller?.present(textAlertController(context: self.context, title: setting, text: "", actions: actions), in: .window(.root))
        }
    }

    func toggle(_ key: String, _ value: Bool) {
        guard !self.busy else { return }
        if key.hasPrefix("render:"), case let .rendered(state) = self.mode, let node = state.node(String(key.dropFirst(7))), node.type == "toggle" { state.invoke(node, value: .bool(value)); self.refresh(); return }
        if key == "afterInstall" { self.enableAfterInstall = value; self.refresh(); return }
        if key == "global" { self.manager.setGloballyEnabled(value); return }
        if key.hasPrefix("enabled:") {
            let id = String(key.dropFirst(8))
            self.manager.setEnabled(id: id, enabled: value) { [weak self] result in
                if case let .failure(error) = result, error.code == "permission_denied" { self?.push(.permissions(id)) }
                self?.complete(result)
            }
        } else if key.hasPrefix("grant:"), case let .permissions(id) = self.mode, let item = self.installation(id), let index = Int(key.dropFirst(6)) {
            let requested = item.manifest.permissions + item.manifest.optionalPermissions
            guard requested.indices.contains(index) else { return }
            var grants = item.grants.filter { $0 != requested[index] }
            if value { grants.append(requested[index]) }
            self.manager.setGrants(id: id, permissions: grants) { [weak self] result in
                guard let self else { return }
                if case .success = result, self.enableAfterInstall, item.manifest.permissions.allSatisfy({ grants.contains($0) }) {
                    self.enableAfterInstall = false
                    self.mode = .details(id)
                    self.manager.setEnabled(id: id, enabled: true) { [weak self] result in self?.complete(result) }
                }
                self.complete(result)
            }
        } else if key.hasPrefix("setting:"), case let .settings(id) = self.mode, let item = self.installation(id) {
            var values = item.settings
            values[String(key.dropFirst(8))] = .bool(value)
            self.manager.updateSettings(id: id, values: values) { [weak self] result in self?.complete(result) }
        }
    }

    func input(_ key: String, _ value: String) {
        if key.hasPrefix("render:"), case let .rendered(state) = self.mode, let node = state.node(String(key.dropFirst(7))), node.type == "input" { state.invoke(node, value: .string(String(value.prefix(4096)))); return }
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

    private func complete(_ result: Result<Void, DGPluginError>) {
        if case let .failure(error) = result { self.showError(error) }
        self.refresh()
    }

    private func showError(_ error: DGPluginError) {
        guard let controller = self.controller else { return }
        controller.present(textAlertController(context: self.context, title: self.tr("не удалось", "unable to complete"), text: error.code + ": " + error.message, actions: [TextAlertAction(type: .defaultAction, title: self.tr("закрыть", "close"), action: {})]), in: .window(.root))
    }

    private func confirm(title: String, text: String, destructive: Bool, action: @escaping () -> Void) {
        self.controller?.present(textAlertController(context: self.context, title: title, text: text, actions: [TextAlertAction(type: .genericAction, title: self.tr("отмена", "cancel"), action: {}), TextAlertAction(type: destructive ? .destructiveAction : .defaultAction, title: self.tr("подтвердить", "confirm"), action: action)]), in: .window(.root))
    }

    private func push(_ mode: DGPluginPageMode) {
        (self.controller?.navigationController as? NavigationController)?.pushViewController(dgMakePluginPage(context: self.context, mode: mode))
    }
}

private func dgMakePluginPage(context: AccountContext, mode: DGPluginPageMode) -> ItemListController {
    let page = DGPluginPage(context: context, mode: mode)
    return dgMakePluginPage(page: page)
}

private func dgMakePluginPage(page: DGPluginPage) -> ItemListController {
    let context = page.context
    dgBindPluginAccount(context: context)
    let signal = combineLatest(context.sharedContext.presentationData, page.revision.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let data = ItemListPresentationData(presentationData)
        let close = ItemListNavigationButton(content: .text(page.tr("закрыть", "close")), style: .regular, enabled: !page.busy, action: { [weak page] in
            guard let controller = page?.controller else { return }
            page?.resourceDisposable?.dispose()
            if let navigation = controller.navigationController as? NavigationController { let _ = navigation.popViewController(animated: true) }
            else { controller.dismiss() }
        })
        let state = ItemListControllerState(presentationData: data, title: .text(page.title), leftNavigationButton: nil, rightNavigationButton: close, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: data, entries: page.rows(), style: .blocks, animateChanges: false), page))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.alwaysSynchronous = true
    page.controller = controller
    return controller
}

public func dgPluginsController(context: AccountContext) -> ViewController {
    return dgMakePluginPage(context: context, mode: .list)
}

public func dgPluginInstallController(context: AccountContext, package: DGVerifiedPluginPackage) -> ViewController {
    return dgMakePluginPage(context: context, mode: .install(package))
}

public func dgPluginRenderedController(context: AccountContext, page: DGPluginJSON, pluginName: String, validity: @escaping () -> Bool, onCallback: @escaping (String, DGPluginJSON) -> Void) throws -> ViewController {
    guard validity() else { throw DGPluginError(code: "cancelled", message: "plugin page is no longer current") }
    let state = try DGPluginRenderedState(page: page, pluginName: pluginName, validity: validity, callback: onCallback)
    return dgMakePluginPage(context: context, mode: .rendered(state))
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

public func dgOpenPluginDocument(context: AccountContext, file: FileMediaReference, present: (ViewController) -> Void) -> Bool {
    let fileName = file.media.fileName ?? ""
    guard fileName.lowercased().hasSuffix(".donut.js") || fileName.lowercased().hasSuffix(".dgplugin") else { return false }
    let page = DGPluginPage(context: context, mode: .loading)
    let controller = dgMakePluginPage(page: page)
    present(controller)
    let limit = 8 * 1024 * 1024
    if let size = file.media.size, size > Int64(limit) {
        page.mode = .failure(page.tr("файл плагина превышает 8 миб", "plugin document exceeds 8 mib"))
        page.refresh()
        return true
    }
    let resource = file.media.resource
    let source = Signal<EngineMediaResource.ResourceData?, NoError> { subscriber in
        let read = (context.engine.resources.data(resource: EngineMediaResource(resource))
        |> filter { $0.isComplete }
        |> take(1)).start(next: { data in subscriber.putNext(data); subscriber.putCompletion() })
        let fetch = context.engine.resources.fetch(reference: file.abstract.resourceReference(resource), userLocation: .other, userContentType: .file).start(error: { _ in subscriber.putNext(nil); subscriber.putCompletion() })
        return ActionDisposable { read.dispose(); fetch.dispose() }
    }
    page.resourceDisposable = (source
    |> timeout(30.0, queue: Queue.mainQueue(), alternate: .single(nil))
    |> take(1)
    |> deliverOn(Queue.concurrentDefaultQueue())
    |> map { resourceData -> Result<DGVerifiedPluginPackage, DGPluginError> in
        guard let resourceData else { return .failure(DGPluginError(code: "download_failed", message: "unable to download plugin document")) }
        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: resourceData.path))
            defer { try? handle.close() }
            let data = try handle.read(upToCount: limit + 1) ?? Data()
            guard data.count <= limit else { throw DGPluginError(code: "package_too_large", message: "plugin document exceeds 8 mib") }
            return .success(try DGPluginInstaller.preview(data: data, fileName: fileName))
        } catch let error as DGPluginError { return .failure(error) }
        catch { return .failure(DGPluginError(code: "invalid_package", message: "unable to read or validate plugin document")) }
    }
    |> deliverOnMainQueue).start(next: { [weak page] result in
        guard let page else { return }
        switch result {
        case let .success(package): page.mode = .install(package)
        case let .failure(error): page.mode = .failure(error.code + ": " + error.message)
        }
        page.refresh()
    })
    return true
}

private let dgPluginDocumentIconCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    cache.countLimit = 64
    cache.totalCostLimit = 4 * 1024 * 1024
    return cache
}()

public func dgPluginDocumentIcon(context: AccountContext, file: TelegramMediaFile) -> Signal<UIImage?, NoError> {
    let name = file.fileName ?? ""
    guard name.lowercased().hasSuffix(".donut.js") || name.lowercased().hasSuffix(".dgplugin") else { return .single(nil) }
    return context.engine.resources.data(resource: EngineMediaResource(file.resource))
    |> filter { $0.isComplete }
    |> take(1)
    |> deliverOn(Queue.concurrentDefaultQueue())
    |> map { resource -> UIImage? in
        do {
            let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: resource.path))
            defer { try? handle.close() }
            let bytes = try handle.read(upToCount: 8 * 1024 * 1024 + 1) ?? Data()
            guard bytes.count <= 8 * 1024 * 1024 else { return nil }
            let digest = DGPluginInstaller.digest(bytes)
            if let image = dgPluginDocumentIconCache.object(forKey: digest as NSString) { return image }
            let package = try DGPluginInstaller.preview(data: bytes, fileName: name)
            let image = dgPluginIcon(data: package.iconData, id: package.manifest.id, name: package.manifest.name)
            dgPluginDocumentIconCache.setObject(image, forKey: digest as NSString, cost: 96 * 96 * 4)
            return image
        } catch { return nil }
    }
}

public func dgPluginIcon(data: Data?, id: String, name: String) -> UIImage {
    if let data, data.count <= 262144, let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) == 1,
       let type = CGImageSourceGetType(source) as String?, ["public.png", "public.jpeg"].contains(type),
       let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
       let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
       width > 0, height > 0, width <= 1024, height <= 1024,
       let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 96, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) {
        return UIImage(cgImage: image, scale: CGFloat(max(image.width, image.height)) / 40.0, orientation: .up)
    }
    var hash: UInt32 = 2166136261
    for byte in id.utf8 { hash = (hash ^ UInt32(byte)) &* 16777619 }
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 40))
    return renderer.image { _ in
        UIColor(hue: CGFloat(hash % 360) / 360, saturation: 0.45, brightness: 0.65, alpha: 1).setFill()
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 40, height: 40), cornerRadius: 9).fill()
        let initials = name.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
        let text = initials.isEmpty ? "DG" : initials
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: UIColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: (40 - size.width) / 2, y: (40 - size.height) / 2), withAttributes: attributes)
    }
}
