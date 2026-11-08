import Foundation
import DGPluginModel

func dgPluginNativePageEnvelope(_ value: DGPluginJSON) -> (page: DGPluginJSON, accent: String?) {
    guard var object = value.objectValue else { return (value, nil) }
    let tokens = object.removeValue(forKey: "__dgThemeTokens")?.objectValue
    let accent = tokens?["accent"]?.stringValue
    return (.object(object), accent.flatMap { ["blue", "green", "purple", "orange"].contains($0) ? $0 : nil })
}

enum DGPluginMarkdownStyle { case body, bold, italic, code, heading }
struct DGPluginMarkdownRun {
    var text: String
    let style: DGPluginMarkdownStyle
}

func dgPluginMarkdownRuns(_ source: String) -> [DGPluginMarkdownRun] {
    let characters = Array(String(decoding: source.utf16.prefix(4096), as: UTF16.self))
    var runs: [DGPluginMarkdownRun] = []
    var bold = false
    var italic = false
    var code = false
    var heading = false
    var lineStart = true
    var index = 0
    func append(_ text: String) {
        let style: DGPluginMarkdownStyle = code ? .code : (heading ? .heading : (bold ? .bold : (italic ? .italic : .body)))
        if runs.last?.style == style { runs[runs.count - 1].text += text }
        else { runs.append(DGPluginMarkdownRun(text: text, style: style)) }
    }
    while index < characters.count {
        let character = characters[index]
        if !code && lineStart {
            if character == "#" {
                var end = index
                while end < characters.count, end - index < 6, characters[end] == "#" { end += 1 }
                if end < characters.count, characters[end] == " " { heading = true; index = end + 1; lineStart = false; continue }
            }
            if (character == "-" || character == "*"), index + 1 < characters.count, characters[index + 1] == " " { append("• "); index += 2; lineStart = false; continue }
        }
        if character == "\\", index + 1 < characters.count { append(String(characters[index + 1])); index += 2; lineStart = false; continue }
        if character == "`" { code.toggle(); index += 1; continue }
        if !code, character == "*", index + 1 < characters.count, characters[index + 1] == "*" { bold.toggle(); index += 2; continue }
        if !code, character == "*" { italic.toggle(); index += 1; continue }
        if !code, character == "[" {
            var closing = index + 1
            while closing < characters.count, closing - index <= 201, characters[closing] != "]", characters[closing] != "\n" { closing += 1 }
            if closing + 1 < characters.count, characters[closing] == "]", characters[closing + 1] == "(" {
                var end = closing + 2
                while end < characters.count, end - closing <= 2049, characters[end] != ")", characters[end] != "\n" { end += 1 }
                if end < characters.count, characters[end] == ")" {
                    append(String(characters[(index + 1)..<closing]))
                    index = end + 1
                    lineStart = false
                    continue
                }
            }
        }
        append(String(character))
        lineStart = character == "\n"
        if lineStart { heading = false }
        index += 1
    }
    return runs
}

struct DGPluginRenderChoice {
    let title: String
    let value: DGPluginJSON
}

struct DGPluginRenderNode {
    let type: String
    let id: String
    let title: String
    let text: String
    let value: DGPluginJSON
    let callbackId: String?
    let options: [DGPluginRenderChoice]
    let children: [DGPluginRenderNode]
    let minimum: Double
    let maximum: Double
    let step: Double
    let asset: String?
}

final class DGPluginRenderedState {
    let title: String
    let pluginName: String
    let nodes: [DGPluginRenderNode]
    let validity: () -> Bool
    let callback: (String, DGPluginJSON) -> Void
    let assetProvider: (String) -> Data?
    var onClose: (() -> Void)?
    private var active = true
    var values: [String: DGPluginJSON] = [:]

    init(page: DGPluginJSON, pluginName: String, validity: @escaping () -> Bool, assetProvider: @escaping (String) -> Data? = { _ in nil }, onClose: (() -> Void)? = nil, callback: @escaping (String, DGPluginJSON) -> Void) throws {
        guard try JSONEncoder().encode(page).count <= 65536, let object = page.objectValue, Set(object.keys).isSubset(of: ["id", "title", "nodes"]), let id = object["id"]?.stringValue, Self.validId(id), let title = object["title"]?.stringValue, !title.isEmpty, Self.validText(title, multiline: false), title.utf16.count <= 200, case let .array(nodes)? = object["nodes"] else { throw DGPluginError(code: "invalid_argument", message: "invalid declarative page") }
        var ids = Set<String>()
        var count = 0
        self.nodes = try Self.parse(nodes, depth: 0, count: &count, ids: &ids)
        self.title = title
        self.pluginName = pluginName
        self.validity = validity
        self.callback = callback
        self.assetProvider = assetProvider
        self.onClose = onClose
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
            guard count <= 128, let node = value.objectValue, Set(node.keys).isSubset(of: ["type", "id", "title", "text", "value", "callbackId", "children", "options", "minimum", "maximum", "step", "asset"]), let type = node["type"]?.stringValue, let id = node["id"]?.stringValue, Self.validId(id), ids.insert(id).inserted else { throw DGPluginError(code: "invalid_argument", message: "invalid or duplicate page node") }
            guard ["section", "text", "markdown", "list", "button", "toggle", "input", "multiline", "select", "slider", "stepper", "image"].contains(type) else { throw DGPluginError(code: "feature_unavailable", message: "unsupported declarative node: " + type) }
            let title = node["title"]?.stringValue ?? ""
            let text = node["text"]?.stringValue ?? ""
            guard (node["title"] == nil || node["title"]?.stringValue != nil), (node["text"] == nil || node["text"]?.stringValue != nil), title.utf16.count <= 200, text.utf16.count <= 4096, Self.validText(title, multiline: false), Self.validText(text, multiline: true) else { throw DGPluginError(code: "invalid_argument", message: "invalid page text") }
            let callbackId = node["callbackId"]?.stringValue
            guard node["callbackId"] == nil || callbackId != nil, node["options"] == nil || type == "select" else { throw DGPluginError(code: "invalid_argument", message: "invalid node options or callback") }
            if ["button", "toggle", "input", "multiline", "select", "slider", "stepper"].contains(type) {
                guard let callbackId, Self.validId(callbackId) else { throw DGPluginError(code: "invalid_argument", message: "interactive nodes require callbackId") }
            } else if callbackId != nil { throw DGPluginError(code: "invalid_argument", message: "noninteractive nodes cannot receive callbacks") }
            let inputValue = node["value"] ?? .null
            if type == "toggle", case .bool = inputValue {} else if type == "toggle" { throw DGPluginError(code: "invalid_argument", message: "toggle value must be boolean") }
            if type == "input" || type == "multiline" { guard let string = inputValue.stringValue, string.utf16.count <= 4096 else { throw DGPluginError(code: "invalid_argument", message: "input value must be bounded text") } }
            var minimum = 0.0
            var maximum = 1.0
            var step = 1.0
            if type == "slider" || type == "stepper" {
                guard case let .number(lower)? = node["minimum"], case let .number(upper)? = node["maximum"], case let .number(increment)? = node["step"], case let .number(number) = inputValue,
                      lower.isFinite, upper.isFinite, increment.isFinite, number.isFinite, abs(lower) <= 1e9, abs(upper) <= 1e9, lower < upper, increment > 0, increment <= upper - lower, number >= lower, number <= upper,
                      (upper - lower) / increment <= 1e6, abs(((number - lower) / increment).rounded() - ((number - lower) / increment)) <= 1e-6 else { throw DGPluginError(code: "invalid_argument", message: "invalid numeric control bounds or value") }
                minimum = lower
                maximum = upper
                step = increment
            } else if node["minimum"] != nil || node["maximum"] != nil || node["step"] != nil { throw DGPluginError(code: "invalid_argument", message: "numeric bounds require a numeric control") }
            let asset = node["asset"]?.stringValue
            if type == "image" {
                guard let asset, !asset.isEmpty, asset.utf8.count <= 128, asset.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil else { throw DGPluginError(code: "invalid_argument", message: "image requires an opaque local asset handle") }
            } else if node["asset"] != nil { throw DGPluginError(code: "invalid_argument", message: "asset handles require image nodes") }
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
            return DGPluginRenderNode(type: type, id: id, title: title, text: text, value: inputValue, callbackId: callbackId, options: options, children: children, minimum: minimum, maximum: maximum, step: step, asset: asset)
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
        guard self.active, self.validity(), let callbackId = node.callbackId else { return }
        self.values[node.id] = value
        self.callback(callbackId, value)
    }

    func close() {
        self.active = false
        let callback = self.onClose
        self.onClose = nil
        callback?()
    }

    func supersede() { self.active = false; self.onClose = nil }
}
