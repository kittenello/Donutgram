import Foundation
import DGPluginModel

@main
struct DGPluginPageSchemaTests {
    static var passed = 0

    static func page(_ nodes: [DGPluginJSON], extra: [String: DGPluginJSON] = [:]) -> DGPluginJSON {
        var value: [String: DGPluginJSON] = ["id": .string("test.page"), "title": .string("test page"), "nodes": .array(nodes)]
        for (key, item) in extra { value[key] = item }
        return .object(value)
    }

    static func node(_ type: String, id: String = "node", fields: [String: DGPluginJSON] = [:]) -> DGPluginJSON {
        var value: [String: DGPluginJSON] = ["id": .string(id), "type": .string(type)]
        for (key, item) in fields { value[key] = item }
        return .object(value)
    }

    static func state(_ value: DGPluginJSON) throws -> DGPluginRenderedState {
        return try DGPluginRenderedState(page: value, pluginName: "verified host name", validity: { true }, callback: { _, _ in })
    }

    static func accepts(_ name: String, _ value: DGPluginJSON) throws {
        let _ = try state(value)
        passed += 1
        print("passed: " + name)
    }

    static func rejects(_ name: String, _ value: DGPluginJSON) throws {
        do { let _ = try state(value) }
        catch { passed += 1; print("passed: " + name); return }
        throw DGPluginError(code: "test_failure", message: "accepted hostile page: " + name)
    }

    static func main() throws {
        for (minimum, maximum, step) in [(0.0, 1.0, 0.3), (-2.0, 0.0, 0.3), (0.0, 1.0, 0.1)] {
            for index in 0...1000 {
                let raw = minimum + Double(index) / 1000 * (maximum - minimum)
                let value = dgPluginNumericControlValue(raw, minimum: minimum, maximum: maximum, step: step)
                let position = (value - minimum) / step
                guard value >= minimum, value <= maximum, abs(position.rounded() - position) <= 1e-6 else { throw DGPluginError(code: "test_failure", message: "numeric control emitted off-grid value") }
            }
        }
        guard abs(dgPluginNumericControlValue(1, minimum: 0, maximum: 1, step: 0.3) - 0.9) < 1e-9 else { throw DGPluginError(code: "test_failure", message: "slider exceeded its last valid step") }
        passed += 1
        try accepts("plain text", page([node("text", fields: ["text": .string("hello")])]))
        try accepts("markdown remains data", page([node("markdown", fields: ["text": .string("# heading\n**bold** <script> literal [label](https://example.org)")])]))
        try accepts("multiline text", page([node("multiline", fields: ["value": .string("one\ntwo"), "callbackId": .string("callback.1")])]))
        try accepts("select null option", page([node("select", fields: ["value": .null, "callbackId": .string("callback.1"), "options": .array([.object(["title": .string("none"), "value": .null])])])]))
        try accepts("opaque local image", page([node("image", fields: ["asset": .string("asset.12345")])]))
        let numeric: [String: DGPluginJSON] = ["value": .number(0.5), "minimum": .number(0), "maximum": .number(1), "step": .number(0.1), "callbackId": .string("callback.2")]
        try accepts("finite slider", page([node("slider", fields: numeric)]))
        try accepts("finite stepper", page([node("stepper", fields: numeric)]))
        try rejects("duplicate ids across containers", page([node("section", id: "parent", fields: ["children": .array([node("text")])]), node("text")]))
        try rejects("unknown native node", page([node("webview")]))
        try rejects("unknown root field", page([], extra: ["url": .string("https://example.org")]))
        try rejects("unknown node field", page([node("text", fields: ["onclick": .string("logout")])]))
        try rejects("text callback", page([node("text", fields: ["callbackId": .string("callback.1")])]))
        try rejects("button without callback", page([node("button")]))
        try rejects("callback identity injection", page([node("button", fields: ["callbackId": .string("../../other")])]))
        try rejects("bidi title", page([node("text", fields: ["title": .string("safe\u{202e}spoof")])]))
        try rejects("control title", page([node("text", fields: ["title": .string("safe\nspoof")])]))
        try rejects("nonstring title", page([node("text", fields: ["title": .number(1)])]))
        try rejects("remote image", page([node("image", fields: ["asset": .string("https://example.org/image.png")])]))
        try rejects("path image", page([node("image", fields: ["asset": .string("assets/private.png")])]))
        try rejects("asset on button", page([node("button", fields: ["asset": .string("asset.1"), "callbackId": .string("callback.1")])]))
        var invalidNumeric = numeric
        invalidNumeric["value"] = .number(0.55)
        try rejects("slider off grid", page([node("slider", fields: invalidNumeric)]))
        invalidNumeric = numeric
        invalidNumeric["step"] = .number(0)
        try rejects("zero numeric step", page([node("stepper", fields: invalidNumeric)]))
        invalidNumeric = numeric
        invalidNumeric["maximum"] = .number(-1)
        try rejects("reversed numeric bounds", page([node("slider", fields: invalidNumeric)]))
        invalidNumeric = numeric
        invalidNumeric["step"] = .number(0.00000000001)
        try rejects("excessive numeric grid", page([node("slider", fields: invalidNumeric)]))
        try rejects("oversized input", page([node("multiline", fields: ["value": .string(String(repeating: "x", count: 4097)), "callbackId": .string("callback.1")])]))
        try rejects("wrong toggle value", page([node("toggle", fields: ["value": .string("true"), "callbackId": .string("callback.1")])]))
        try rejects("nodes count", page((0..<129).map { node("text", id: "node.\($0)") }))
        var nested = node("text", id: "leaf")
        for index in 0..<8 { nested = node("section", id: "depth.\(index)", fields: ["children": .array([nested])]) }
        try rejects("depth limit", page([nested]))
        try rejects("children on action", page([node("button", fields: ["callbackId": .string("callback.1"), "children": .array([])])]))
        try rejects("select undeclared value", page([node("select", fields: ["value": .string("secret"), "callbackId": .string("callback.1"), "options": .array([.object(["title": .string("public"), "value": .string("public")])])])]))
        var active = true
        var callbacks = 0
        var closed = 0
        let live = try DGPluginRenderedState(page: page([node("toggle", fields: ["value": .bool(false), "callbackId": .string("callback.1")])]), pluginName: "host", validity: { active }, onClose: { closed += 1 }, callback: { _, _ in callbacks += 1 })
        let control = live.node("node")!
        live.invoke(control, value: .bool(true))
        active = false
        live.invoke(control, value: .bool(false))
        guard callbacks == 1 else { throw DGPluginError(code: "test_failure", message: "revoked callback was delivered") }
        passed += 1
        live.close()
        live.close()
        guard closed == 1 else { throw DGPluginError(code: "test_failure", message: "close was not exactly once") }
        passed += 1
        var retiredCallbacks = 0
        let retired = try DGPluginRenderedState(page: page([node("toggle", fields: ["value": .bool(false), "callbackId": .string("callback.1")])]), pluginName: "host", validity: { true }, callback: { _, _ in retiredCallbacks += 1 })
        retired.supersede()
        retired.invoke(retired.node("node")!, value: .bool(true))
        guard retiredCallbacks == 0 else { throw DGPluginError(code: "test_failure", message: "superseded page delivered callback") }
        passed += 1
        let markdown = dgPluginMarkdownRuns("# title\n- **bold** and *italic* and `code` [label](https://example.org/private) <script>literal</script>")
        let plain = markdown.map { $0.text }.joined()
        guard plain.contains("title\n• bold"), plain.contains("label"), !plain.contains("https://"), plain.contains("<script>literal</script>"), markdown.contains(where: { $0.style == .heading }), markdown.contains(where: { $0.style == .bold }), markdown.contains(where: { $0.style == .italic }), markdown.contains(where: { $0.style == .code }) else { throw DGPluginError(code: "test_failure", message: "bounded markdown emitted unexpected content or formatting") }
        passed += 1
        let bounded = dgPluginMarkdownRuns(String(repeating: "[", count: 20000)).map { $0.text }.joined()
        guard bounded.utf16.count == 4096 else { throw DGPluginError(code: "test_failure", message: "markdown input was not bounded") }
        passed += 1
        let themed = page([], extra: ["__dgThemeTokens": .object(["accent": .string("green")])])
        try rejects("public schema rejects reserved native theme envelope", themed)
        let envelope = dgPluginNativePageEnvelope(themed)
        guard envelope.accent == "green", envelope.page == page([]) else { throw DGPluginError(code: "test_failure", message: "native theme envelope was not separated") }
        passed += 1
        let unsupported = dgPluginNativePageEnvelope(page([], extra: ["__dgThemeTokens": .object(["accent": .string("#00ff00")])]))
        guard unsupported.accent == nil, unsupported.page == page([]) else { throw DGPluginError(code: "test_failure", message: "arbitrary theme color was accepted") }
        passed += 1
        print("passed \(passed) real declarative schema checks")
    }
}
