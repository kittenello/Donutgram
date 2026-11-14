import Foundation
import DGPluginModel

public enum DGPluginOutgoingMessage {
    public static func replacementPreservesAttributes(_ original: NSAttributedString, range: NSRange) -> Bool {
        guard range.location >= 0, range.length >= 0, range.location <= original.length, range.length <= original.length - range.location else { return false }
        let inspected: NSRange
        if range.length == 0 {
            let start = max(0, range.location - 1)
            inspected = NSRange(location: start, length: min(original.length, range.location + 1) - start)
        } else {
            inspected = range
        }
        var safe = true
        original.enumerateAttributes(in: inspected) { attributes, _, stop in
            if !attributes.isEmpty { safe = false; stop.pointee = true }
        }
        return safe
    }

    public static func replacementEdit(original: String, replacement: String) -> (range: NSRange, text: String) {
        let old = Array(original.unicodeScalars)
        let new = Array(replacement.unicodeScalars)
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix, old[old.count - suffix - 1] == new[new.count - suffix - 1] { suffix += 1 }
        let start = String(String.UnicodeScalarView(old[..<prefix])).utf16.count
        let removed = String(String.UnicodeScalarView(old[prefix..<(old.count - suffix)])).utf16.count
        let inserted = String(String.UnicodeScalarView(new[prefix..<(new.count - suffix)]))
        return (NSRange(location: start, length: removed), inserted)
    }

    public static func input(_ text: String) throws -> DGPluginJSON {
        guard !text.isEmpty, text.utf16.count <= 4096 else { throw DGPluginError(code: "invalid_argument", message: "outgoing text exceeds the ordinary message limit") }
        return .object(["text": .string(text), "cancelled": .bool(false)])
    }

    public static func apply(input: DGPluginJSON, patch: DGPluginJSON) throws -> DGPluginJSON {
        guard let original = input.objectValue, let text = original["text"]?.stringValue,
              let values = patch.objectValue, Set(values.keys).isSubset(of: ["text", "cancel"]),
              values["cancel"] == nil || values["cancel"] == .bool(false) || values["cancel"] == .bool(true) else { throw DGPluginError(code: "invalid_argument", message: "invalid outgoing message replacement") }
        let replacement = values["text"]?.stringValue ?? text
        guard values["text"] == nil || values["text"]?.stringValue != nil,
              !replacement.isEmpty, replacement.utf16.count <= 4096 else { throw DGPluginError(code: "invalid_argument", message: "invalid outgoing message text") }
        return .object(["text": .string(replacement), "cancelled": .bool(original["cancelled"] == .bool(true) || values["cancel"] == .bool(true))])
    }
}
