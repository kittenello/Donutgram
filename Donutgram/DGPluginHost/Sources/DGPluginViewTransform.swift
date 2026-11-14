import Foundation
import DGPluginModel

public enum DGPluginViewTransform {
    public static func validateInput(slot: String, input: DGPluginJSON) throws {
        try input.validateLimits(maximumDepth: 8, maximumNodes: 4096)
        guard try JSONEncoder().encode(input).count <= 32768, let object = input.objectValue else { throw invalid() }
        if slot == "profile" {
            guard Set(object.keys) == ["panes"], case let .array(panes)? = object["panes"], panes.count <= 32 else { throw invalid() }
            var ids = Set<String>()
            for pane in panes {
                guard let value = pane.objectValue, Set(value.keys) == ["id", "empty"], let id = value["id"]?.stringValue, validId(id), ids.insert(id).inserted, case .bool? = value["empty"] else { throw invalid() }
            }
        } else if slot == "chatList" || slot == "displayLinks" {
            guard Set(object.keys) == ["items"], case let .array(items)? = object["items"], items.count <= 128 else { throw invalid() }
            var handles = Set<String>()
            for item in items {
                guard let value = item.objectValue, let handle = value["handle"]?.stringValue, validId(handle), handles.insert(handle).inserted else { throw invalid() }
                if slot == "chatList" {
                    guard Set(value.keys) == ["handle", "title", "unread", "pinned"], let title = value["title"]?.stringValue, title.utf16.count <= 256, case let .number(unread)? = value["unread"], unread.isFinite, unread >= 0, unread <= 1_000_000, unread.rounded() == unread, case .bool? = value["pinned"] else { throw invalid() }
                } else {
                    guard Set(value.keys) == ["handle", "title", "url"], let title = value["title"]?.stringValue, title.utf16.count <= 512, let url = value["url"]?.stringValue, url.utf8.count <= 2048 else { throw invalid() }
                }
            }
        } else { throw DGPluginError(code: "feature_unavailable", message: "unknown local view-model slot") }
    }

    public static func apply(slot: String, input: DGPluginJSON, patch: DGPluginJSON) throws -> DGPluginJSON {
        try validateInput(slot: slot, input: input)
        try patch.validateLimits(maximumDepth: 8, maximumNodes: 4096)
        guard try JSONEncoder().encode(patch).count <= 32768, let object = patch.objectValue, let source = input.objectValue else { throw invalid() }
        if slot == "profile" {
            guard Set(object.keys) == ["hide"], case let .array(requested)? = object["hide"], case let .array(panes)? = source["panes"] else { throw invalid() }
            let hidden = try stringSet(requested)
            let empty = Set(panes.compactMap { value -> String? in guard let pane = value.objectValue, pane["empty"] == .bool(true) else { return nil }; return pane["id"]?.stringValue })
            guard hidden.isSubset(of: empty) else { throw DGPluginError(code: "scope_denied", message: "only known empty profile panes may be hidden") }
            return .object(["panes": .array(panes.filter { !hidden.contains($0.objectValue?["id"]?.stringValue ?? "") })])
        }
        guard case let .array(items)? = source["items"] else { throw invalid() }
        if slot == "chatList" {
            guard Set(object.keys).isSubset(of: ["order", "hidden"]), case let .array(order) = object["order"] ?? .array([]), case let .array(hiddenValues) = object["hidden"] ?? .array([]) else { throw invalid() }
            let ordered = try stringSet(order), hidden = try stringSet(hiddenValues)
            let unpinned = items.filter { $0.objectValue?["pinned"] == .bool(false) }
            let permitted = Set(unpinned.compactMap { $0.objectValue?["handle"]?.stringValue })
            guard ordered.isSubset(of: permitted), hidden.isSubset(of: permitted) else { throw DGPluginError(code: "scope_denied", message: "pinned or unknown chats cannot be moved or hidden") }
            let ranks = Dictionary(uniqueKeysWithValues: order.enumerated().compactMap { index, value in value.stringValue.map { ($0, index) } })
            let sorted = unpinned.enumerated().filter { !hidden.contains($0.element.objectValue?["handle"]?.stringValue ?? "") }.sorted { lhs, rhs in
                let left = ranks[lhs.element.objectValue?["handle"]?.stringValue ?? ""] ?? Int.max
                let right = ranks[rhs.element.objectValue?["handle"]?.stringValue ?? ""] ?? Int.max
                return left == right ? lhs.offset < rhs.offset : left < right
            }.map { $0.element }
            return .object(["items": .array(items.filter { $0.objectValue?["pinned"] == .bool(true) } + sorted)])
        }
        guard Set(object.keys) == ["labels"], case let .array(labels)? = object["labels"], labels.count <= items.count else { throw invalid() }
        let permitted = Set(items.compactMap { $0.objectValue?["handle"]?.stringValue })
        var replacements: [String: String] = [:]
        for label in labels {
            guard let value = label.objectValue, Set(value.keys) == ["handle", "text"], let handle = value["handle"]?.stringValue, permitted.contains(handle), replacements[handle] == nil, let text = value["text"]?.stringValue, !text.isEmpty, text.utf16.count <= 512, text.unicodeScalars.allSatisfy({ $0.value >= 32 && !(127 ... 159).contains($0.value) && !(0x2028 ... 0x202e).contains($0.value) && !(0x2066 ... 0x2069).contains($0.value) }) else { throw invalid() }
            replacements[handle] = text
        }
        return .object(["items": .array(items.map { item in
            var value = item.objectValue!
            if let handle = value["handle"]?.stringValue, let title = replacements[handle] { value["title"] = .string(title) }
            return .object(value)
        })])
    }

    private static func stringSet(_ values: [DGPluginJSON]) throws -> Set<String> {
        let strings = values.compactMap { $0.stringValue }
        let result = Set(strings)
        guard strings.count == values.count, result.count == values.count else { throw invalid() }
        return result
    }

    private static func validId(_ value: String) -> Bool { return value.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", options: .regularExpression) != nil }
    private static func invalid() -> DGPluginError { return DGPluginError(code: "invalid_argument", message: "invalid local view-model transform") }
}
