import Foundation
import DGPluginModel
import DGPluginNetwork

public struct DGPluginMethodRule {
    public let capability: String?
    public let scope: String?
    public let requiresGesture: Bool
    public let available: Bool
}

public enum DGPluginPolicy {
    public static let methods: [String: DGPluginMethodRule] = {
        var result: [String: DGPluginMethodRule] = [:]
        func add(_ names: [String], _ capability: String?, _ scope: String?, gesture: Bool = false, available: Bool = true) {
            for name in names {
                result[name] = DGPluginMethodRule(capability: capability, scope: scope, requiresGesture: gesture, available: available)
            }
        }
        add(["capabilities.has", "capabilities.list", "environment.get", "settings.get"], nil, nil)
        add(["settings.set"], nil, nil)
        add(["storage.get", "storage.set", "storage.remove", "storage.keys"], "storage.local", "pluginAccount")
        add(["ui.command.register", "ui.command.unregister", "ui.toast"], "ui.contribute", nil)
        add(["ui.render", "ui.dispose"], "ui.contribute", "settings")
        add(["assets.image"], "ui.contribute", "settings")
        add(["events.subscribe", "events.unsubscribe"], nil, nil)
        add(["theme.get"], "theme.read", "currentTheme")
        add(["theme.contribute", "theme.clear"], "theme.contribute", "localTokens")
        add(["composer.getActiveDraft"], "composer.read", "activeComposer", gesture: true)
        add(["composer.replaceSelection"], "composer.transform", "activeComposer", gesture: true)
        add(["selection.get"], "messages.selection.read", "activeSelection", gesture: true)
        add(["messages.read"], "messages.read", "selectedChats", gesture: true)
        add(["chats.metadata"], "chats.metadata.read", "selectedChats", gesture: true)
        add(["peers.read"], "peers.read", "selectedPeers", gesture: true)
        add(["network.request"], "network.public", "declaredOrigins", available: DGPluginPublicNetwork.isAvailable)
        add(["translation.request"], "translation.request", "selectedText", gesture: true)
        add(["navigation.open"], "navigation.open", "safeScreens", gesture: true)
        add(["notifications.local"], "notifications.local", "pluginAccount", gesture: true)
        add(["files.pick", "files.read"], "files.userSelected", "selectedFile", gesture: true)
        add(["messages.send"], "messages.send", "chosenRecipient")
        add(["messages.edit"], "messages.edit", "selectedMessages")
        add(["messages.delete"], "messages.delete", "selectedMessages")
        add(["messages.interceptor.register", "messages.interceptor.unregister", "messages.interceptor.result"], "messages.intercept", "activeComposer")
        add(["messages.compose"], "messages.compose", "chosenRecipient", gesture: true)
        add(["messages.prepare", "messages.sendInteractive"], "messages.sendInteractive", "chosenRecipient", gesture: true)
        add(["ui.transform.register", "ui.transform.unregister", "ui.transform.result"], "ui.transform", nil)
        return result
    }()

    public static func permissionKey(_ permission: DGPluginPermission) -> String {
        return permission.capability + "\u{001f}" + permission.scope + "\u{001f}" + permission.origins.sorted().joined(separator: "\u{001e}")
    }

    public static func validateProfile(_ manifest: DGPluginManifest) throws {
        let permissions = manifest.permissions + manifest.optionalPermissions
        let privateCapabilities: Set<String> = ["composer.read", "composer.transform", "messages.selection.read", "messages.read", "chats.metadata.read", "peers.read", "messages.compose", "messages.sendInteractive", "messages.send", "messages.edit", "messages.delete", "messages.intercept", "files.userSelected", "translation.request", "ui.transform"]
        if manifest.profile == "localPrivate" {
            guard !permissions.contains(where: { $0.capability == "network.public" || $0.capability == "notifications.local" }) else {
                throw DGPluginError(code: "permission_denied", message: "private plugins cannot request public network access")
            }
        } else if manifest.profile == "publicNetwork" {
            guard !permissions.contains(where: { privateCapabilities.contains($0.capability) }) else {
                throw DGPluginError(code: "permission_denied", message: "network plugins cannot request private account data")
            }
        } else {
            throw DGPluginError(code: "invalid_argument", message: "unknown execution profile")
        }
    }

    public static func validateSettings(_ values: [String: DGPluginJSON], manifest: DGPluginManifest) throws {
        guard case let .object(schema)? = manifest.settingsSchema, case let .object(properties)? = schema["properties"] else {
            guard values.isEmpty else { throw DGPluginError(code: "invalid_argument", message: "plugin has no settings schema") }
            return
        }
        guard values.count <= 64 else { throw DGPluginError(code: "quota_exceeded", message: "too many settings") }
        for (key, value) in values {
            guard case let .object(specification)? = properties[key], case let .string(type)? = specification["type"] else {
                throw DGPluginError(code: "invalid_argument", message: "unknown plugin setting")
            }
            var valid = false
            switch (type, value) {
            case ("boolean", .bool): valid = true
            case let ("string", .string(text)):
                let limit = specification["maxLength"]?.dgNumber.map { Int(max(0, min(4096, $0))) } ?? 4096
                valid = text.utf16.count <= limit
            case let ("number", .number(number)), let ("integer", .number(number)):
                valid = number.isFinite && (type != "integer" || number.rounded() == number)
                if let minimum = specification["minimum"]?.dgNumber { valid = valid && number >= minimum }
                if let maximum = specification["maximum"]?.dgNumber { valid = valid && number <= maximum }
            default: break
            }
            if case let .array(choices)? = specification["enum"] { valid = valid && choices.contains(value) }
            guard valid else { throw DGPluginError(code: "invalid_argument", message: "setting does not match its schema") }
        }
        guard try JSONEncoder().encode(values).count <= 65536 else {
            throw DGPluginError(code: "quota_exceeded", message: "settings exceed their quota")
        }
    }

    public static func settingsDefaults(_ manifest: DGPluginManifest) -> [String: DGPluginJSON] {
        guard case let .object(schema)? = manifest.settingsSchema, case let .object(properties)? = schema["properties"] else { return [:] }
        var result: [String: DGPluginJSON] = [:]
        for (key, specification) in properties {
            if case let .object(specification) = specification, let value = specification["default"] { result[key] = value }
        }
        do { try validateSettings(result, manifest: manifest); return result } catch { return [:] }
    }
}

extension DGPluginJSON {
    var dgString: String? { if case let .string(value) = self { return value }; return nil }
    var dgNumber: Double? { if case let .number(value) = self { return value }; return nil }
    var dgObject: [String: DGPluginJSON]? { if case let .object(value) = self { return value }; return nil }
}
