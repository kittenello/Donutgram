import Foundation
import DGPluginModel

public struct DGPluginLocalChatRow: Equatable {
    public let handle: String
    public let title: String
    public let unread: Int
    public let pinned: Bool

    public init(handle: String, title: String, unread: Int, pinned: Bool) {
        self.handle = handle
        self.title = String(decoding: title.utf16.prefix(128), as: UTF16.self)
        self.unread = min(1000000, max(0, unread))
        self.pinned = pinned
    }

    public var json: DGPluginJSON {
        return .object(["handle": .string(self.handle), "title": .string(self.title), "unread": .number(Double(self.unread)), "pinned": .bool(self.pinned)])
    }
}

public enum DGPluginLocalChatProjection {
    public static func input(_ rows: [DGPluginLocalChatRow]) -> DGPluginJSON { return .object(["items": .array(rows.map { $0.json })]) }

    public static func handles(rows: [DGPluginLocalChatRow], output: DGPluginJSON) -> [String]? {
        guard rows.count <= 40, Set(rows.map { $0.handle }).count == rows.count, case let .array(items)? = output.objectValue?["items"], items.count <= rows.count else { return nil }
        let source = Dictionary(uniqueKeysWithValues: rows.map { ($0.handle, $0.json) })
        var handles: [String] = []
        var found = Set<String>()
        for value in items {
            guard let handle = value.objectValue?["handle"]?.stringValue, source[handle] == value, found.insert(handle).inserted else { return nil }
            handles.append(handle)
        }
        let pinned = rows.filter { $0.pinned }.map { $0.handle }
        guard Array(handles.prefix(pinned.count)) == pinned else { return nil }
        if handles.count == pinned.count, let anchor = rows.first(where: { !$0.pinned }) { handles.append(anchor.handle) }
        return handles
    }
}

public enum DGPluginEmptyPaneProjection {
    public static func ids(source: [String], knownEmpty: Set<String>, requested: Set<String>) -> [String] {
        let result = source.filter { requested.contains($0) || !knownEmpty.contains($0) }
        return result.isEmpty ? source : result
    }
}
