import Foundation
import DGPluginModel

public enum DGPluginOutgoingMessage {
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
