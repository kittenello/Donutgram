import Foundation
import XCTest
import DGPluginModel
import DGPluginHost

final class DGPluginPolicyTests: XCTestCase {
    private func manifest(profile: String = "localPrivate", permissions: [DGPluginPermission] = [], settings: DGPluginJSON? = nil) -> DGPluginManifest {
        return DGPluginManifest(id: "dev.example.policy", name: "policy", version: "1.0.0", description: "policy test", permissions: permissions, settingsSchema: settings, profile: profile)
    }

    func testForbiddenEffectsHaveNoMethodRule() {
        for method in ["account.logout", "account.delete", "sessions.terminate", "auth.getKey", "keychain.read", "payments.transfer", "stars.spend", "gifts.transfer", "messages.delete", "messages.send", "rawRequest", "runNative", "objc.invoke", "postbox.get", "permissions.grant", "plugins.install"] {
            XCTAssertNil(DGPluginPolicy.methods[method], method)
        }
    }

    func testBridgeJsonNestingIsBoundedBeforeCustomDecodingRecurses() {
        let input = String(repeating: "[", count: 80) + "null" + String(repeating: "]", count: 80)
        XCTAssertThrowsError(try JSONDecoder().decode(DGPluginJSON.self, from: Data(input.utf8)))
        XCTAssertEqual(try JSONDecoder().decode(DGPluginJSON.self, from: Data("{\"a\":[1,true,null]}".utf8)), .object(["a": .array([.number(1), .bool(true), .null])]))
        var nested = DGPluginJSON.null
        for _ in 0 ..< 30 { nested = .array([nested]) }
        XCTAssertThrowsError(try nested.validateLimits())
        XCTAssertThrowsError(try DGPluginJSON.array(Array(repeating: .null, count: 8192)).validateLimits())
        XCTAssertThrowsError(try DGPluginJSON.number(.infinity).validateLimits())
    }

    func testUnavailableAdaptersFailClosed() {
        XCTAssertNil(DGPluginPolicy.methods["ui.transform"])
        for method in ["composer.getActiveDraft", "composer.replaceSelection", "selection.get", "messages.read", "peers.read", "chats.metadata", "messages.prepare", "messages.sendInteractive", "navigation.open", "files.pick", "files.read", "notifications.local", "translation.request"] {
            XCTAssertEqual(DGPluginPolicy.methods[method]?.requiresGesture, true, method)
        }
    }

    func testProfileSeparationIncludesOptionalPermissions() {
        let network = DGPluginPermission(capability: "network.public", scope: "declaredOrigins", reason: "test", origins: ["https://example.org"])
        let privateData = DGPluginPermission(capability: "composer.read", scope: "activeComposer", reason: "test")
        XCTAssertThrowsError(try DGPluginPolicy.validateProfile(self.manifest(permissions: [network])))
        XCTAssertThrowsError(try DGPluginPolicy.validateProfile(self.manifest(profile: "publicNetwork", permissions: [privateData])))
        let optional = DGPluginManifest(id: "dev.example.policy", name: "policy", version: "1.0.0", description: "test", optionalPermissions: [network])
        XCTAssertThrowsError(try DGPluginPolicy.validateProfile(optional))
        XCTAssertNoThrow(try DGPluginPolicy.validateProfile(self.manifest(profile: "publicNetwork", permissions: [network])))
        XCTAssertThrowsError(try DGPluginPolicy.validateProfile(self.manifest(profile: "allowEverything")))
    }

    func testPermissionKeysDoNotWidenScopeOrOrigins() {
        let first = DGPluginPermission(capability: "network.public", scope: "declaredOrigins", reason: "one", origins: ["https://a.example", "https://b.example"])
        let reordered = DGPluginPermission(capability: "network.public", scope: "declaredOrigins", reason: "two", origins: Array(first.origins.reversed()))
        let widened = DGPluginPermission(capability: "network.public", scope: "declaredOrigins", reason: "one", origins: first.origins + ["https://c.example"])
        let otherScope = DGPluginPermission(capability: "network.public", scope: "all", reason: "one", origins: first.origins)
        XCTAssertEqual(DGPluginPolicy.permissionKey(first), DGPluginPolicy.permissionKey(reordered))
        XCTAssertNotEqual(DGPluginPolicy.permissionKey(first), DGPluginPolicy.permissionKey(widened))
        XCTAssertNotEqual(DGPluginPolicy.permissionKey(first), DGPluginPolicy.permissionKey(otherScope))
    }

    func testSettingsValidateTypeBoundsEnumAndUnknownKeys() throws {
        let schema: DGPluginJSON = .object(["type": .string("object"), "properties": .object([
            "count": .object(["type": .string("integer"), "title": .string("count"), "minimum": .number(1), "maximum": .number(5), "default": .number(2)]),
            "label": .object(["type": .string("string"), "title": .string("label"), "maxLength": .number(4), "enum": .array([.string("safe"), .string("ok")]), "default": .string("safe")]),
            "enabled": .object(["type": .string("boolean"), "title": .string("enabled"), "default": .bool(true)])
        ])])
        let manifest = self.manifest(settings: schema)
        XCTAssertNoThrow(try DGPluginPolicy.validateSettings(["count": .number(3), "label": .string("ok"), "enabled": .bool(false)], manifest: manifest))
        let invalidValues: [[String: DGPluginJSON]] = [
            ["count": .number(0)], ["count": .number(6)], ["count": .number(1.5)], ["count": .number(.infinity)],
            ["enabled": .number(1)], ["label": .string("longer")], ["label": .string("no")], ["unknown": .bool(true)]
        ]
        for values in invalidValues {
            XCTAssertThrowsError(try DGPluginPolicy.validateSettings(values, manifest: manifest))
        }
        XCTAssertEqual(DGPluginPolicy.settingsDefaults(manifest), ["count": .number(2), "label": .string("safe"), "enabled": .bool(true)])
        XCTAssertThrowsError(try DGPluginPolicy.validateSettings(["unknown": .bool(true)], manifest: self.manifest()))
    }

    func testLocalTransformsCannotHideNonemptyOrPinnedContent() throws {
        let profile: DGPluginJSON = .object(["panes": .array([
            .object(["id": .string("media"), "empty": .bool(true)]),
            .object(["id": .string("files"), "empty": .bool(false)])
        ])])
        let expected: DGPluginJSON = .object(["panes": .array([.object(["id": .string("files"), "empty": .bool(false)])])])
        XCTAssertEqual(try DGPluginViewTransform.apply(slot: "profile", input: profile, patch: .object(["hide": .array([.string("media")])])), expected)
        for ids in [["files"], ["unknown"], ["media", "media"]] {
            XCTAssertThrowsError(try DGPluginViewTransform.apply(slot: "profile", input: profile, patch: .object(["hide": .array(ids.map(DGPluginJSON.string))])))
        }
        let items: [DGPluginJSON] = [
            .object(["handle": .string("p1"), "title": .string("first pinned"), "unread": .number(0), "pinned": .bool(true)]),
            .object(["handle": .string("p2"), "title": .string("second pinned"), "unread": .number(1), "pinned": .bool(true)]),
            .object(["handle": .string("u1"), "title": .string("one"), "unread": .number(2), "pinned": .bool(false)]),
            .object(["handle": .string("u2"), "title": .string("two"), "unread": .number(3), "pinned": .bool(false)])
        ]
        let chats: DGPluginJSON = .object(["items": .array(items)])
        XCTAssertEqual(try DGPluginViewTransform.apply(slot: "chatList", input: chats, patch: .object(["order": .array([.string("u2")])])), .object(["items": .array([items[0], items[1], items[3], items[2]])]))
        let invalidPatches: [DGPluginJSON] = [.object(["hidden": .array([.string("p1")])]), .object(["order": .array([.string("p2")])]), .object(["order": .array([.string("unknown")])]), .object(["hidden": .array([.string("u1"), .string("u1")])])]
        for patch in invalidPatches {
            XCTAssertThrowsError(try DGPluginViewTransform.apply(slot: "chatList", input: chats, patch: patch))
        }
    }

    func testDisplayLinkTransformsKeepDestinationsAndRejectControls() throws {
        let input: DGPluginJSON = .object(["items": .array([.object(["handle": .string("link1"), "title": .string("original"), "url": .string("https://example.org/unchanged")])])])
        let patch: DGPluginJSON = .object(["labels": .array([.object(["handle": .string("link1"), "text": .string("clean label")])])])
        let result = try DGPluginViewTransform.apply(slot: "displayLinks", input: input, patch: patch)
        XCTAssertEqual(result, .object(["items": .array([.object(["handle": .string("link1"), "title": .string("clean label"), "url": .string("https://example.org/unchanged")])])]))
        let destinationPatch: DGPluginJSON = .object(["labels": .array([.object(["handle": .string("link1"), "text": .string("label"), "url": .string("https://attacker.example")])])])
        XCTAssertThrowsError(try DGPluginViewTransform.apply(slot: "displayLinks", input: input, patch: destinationPatch))
        for text in ["line\nbreak", "bad\u{007f}", "bad\u{0085}", "bad\u{202e}", "bad\u{2066}"] {
            let controlPatch: DGPluginJSON = .object(["labels": .array([.object(["handle": .string("link1"), "text": .string(text)])])])
            XCTAssertThrowsError(try DGPluginViewTransform.apply(slot: "displayLinks", input: input, patch: controlPatch))
        }
    }
}
