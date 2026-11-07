import Foundation
import CryptoKit
import ImageIO
import DGPluginModel

public struct DGVerifiedPluginPackage {
    public let manifest: DGPluginManifest
    public let files: [String: Data]
    public let digest: String
    public let publisherIdentity: String
    public let trust: String
    public let originalData: Data
    public let iconData: Data?
    public let fileName: String
}

public enum DGPluginInstaller {
    public static func digest(_ data: Data) -> String {
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    public static func preview(data: Data, fileName: String) throws -> DGVerifiedPluginPackage {
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024 else { throw self.error("package_limit", "plugin package exceeds limits") }
        let data = data.withUnsafeBytes { Data(bytes: $0.baseAddress!, count: $0.count) }
        let files: [String: Data]
        let json: DGPluginJSON
        if fileName.lowercased().hasSuffix(".donut.js") {
            guard data.count <= 1024 * 1024, String(data: data, encoding: .utf8) != nil else { throw self.error("invalid_source", "invalid plugin source") }
            var parser = DGStaticJSONParser(data)
            json = try parser.singleFileManifest()
            files = ["main.js": data]
        } else if fileName.lowercased().hasSuffix(".dgplugin") {
            files = try DGBoundedArchive(data: data).files()
            guard let manifest = files["manifest.json"], manifest.count <= 131072 else { throw self.error("invalid_manifest", "manifest.json is missing or oversized") }
            var parser = DGStaticJSONParser(manifest)
            json = try parser.complete()
        } else { throw self.error("not_plugin", "this document is not a plugin") }
        let manifest = try self.manifest(json)
        guard let entry = files[manifest.entry], entry.count <= 1024 * 1024, String(data: entry, encoding: .utf8) != nil else { throw self.error("invalid_entry", "plugin entry is missing or invalid") }
        var marker = DGStaticJSONParser(entry)
        try marker.marker()
        for (name, contents) in files {
            try self.validatePath(name)
            let ext = (name as NSString).pathExtension.lowercased()
            guard ["js", "json", "png", "jpg", "jpeg", "webp"].contains(ext) else { throw self.error("unsupported_resource", "unsupported package resource") }
            let archivePrefixes: [[UInt8]] = [[0x50, 0x4b, 0x03, 0x04], [0x50, 0x4b, 0x05, 0x06], [0x1f, 0x8b], [0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c], [0x52, 0x61, 0x72, 0x21], [0xfd, 0x37, 0x7a, 0x58, 0x5a, 0x00], [0x42, 0x5a, 0x68]]
            guard !archivePrefixes.contains(where: { contents.starts(with: $0) }) else { throw self.error("unsupported_resource", "nested archives are not supported") }
            if ext == "js" {
                guard contents.count <= 1024 * 1024, String(data: contents, encoding: .utf8) != nil else { throw self.error("invalid_source", "invalid javascript module") }
            }
        }
        if fileName.lowercased().hasSuffix(".donut.js"), manifest.entry != "main.js" { throw self.error("invalid_entry", "single-file plugins must use main.js") }
        let signature = try self.signature(files: files, manifest: json)
        let icon = manifest.icon.flatMap { files[$0] }.flatMap(self.safeIcon)
        return DGVerifiedPluginPackage(manifest: manifest, files: files, digest: self.digest(data), publisherIdentity: signature.publisher, trust: signature.trust, originalData: data, iconData: icon, fileName: fileName.lowercased().hasSuffix(".donut.js") ? "plugin.donut.js" : "plugin.dgplugin")
    }

    static func validatePath(_ path: String) throws {
        guard !path.isEmpty, path.utf8.count <= 240, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.contains("%"), path == path.precomposedStringWithCanonicalMapping else { throw self.error("invalid_path", "invalid package path") }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count <= 8, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasSuffix(".") && !$0.hasSuffix(" ") }), path.utf8.allSatisfy({ (65 ... 90).contains($0) || (97 ... 122).contains($0) || (48 ... 57).contains($0) || [UInt8(45), 46, 47, 95].contains($0) }) else { throw self.error("invalid_path", "invalid package path") }
    }

    private static func manifest(_ json: DGPluginJSON) throws -> DGPluginManifest {
        guard let fields = json.objectValue else { throw self.error("invalid_manifest", "manifest must be an object") }
        try self.keys(fields, allowed: ["kind", "schemaVersion", "id", "name", "version", "description", "author", "apiVersion", "minClientVersion", "entry", "icon", "permissions", "optionalPermissions", "settingsSchema", "profile", "changelog"])
        if let author = fields["author"] {
            guard let object = author.objectValue else { throw self.error("invalid_manifest", "invalid author") }
            try self.keys(object, allowed: ["name", "username"])
        }
        for key in ["permissions", "optionalPermissions"] {
            if let value = fields[key] {
                guard case let .array(values) = value, values.count <= 32 else { throw self.error("invalid_permissions", "invalid permissions") }
                for value in values {
                    guard let object = value.objectValue else { throw self.error("invalid_permissions", "invalid permission") }
                    try self.keys(object, allowed: ["capability", "scope", "reason", "origins"])
                }
            }
        }
        let encoded = try JSONEncoder().encode(json)
        let manifest: DGPluginManifest
        do { manifest = try JSONDecoder().decode(DGPluginManifest.self, from: encoded) }
        catch { throw self.error("invalid_manifest", "manifest fields are missing or invalid") }
        guard manifest.kind == "donutgram.plugin", manifest.schemaVersion == 1 else { throw self.error("incompatible", "unsupported plugin schema") }
        guard manifest.id.range(of: "^[a-z](?:[a-z0-9-]*[a-z0-9])?(\\.[a-z](?:[a-z0-9-]*[a-z0-9])?){2,}$", options: .regularExpression) != nil, manifest.id.utf8.count <= 128 else { throw self.error("invalid_identity", "invalid plugin id") }
        guard (1 ... 80).contains(manifest.name.count), !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              manifest.description.count <= 4096, manifest.changelog?.count ?? 0 <= 8192,
              manifest.author?.name.count ?? 0 <= 128, manifest.author?.username?.count ?? 0 <= 64 else { throw self.error("invalid_manifest", "plugin metadata exceeds limits") }
        guard self.displayText(manifest.name), self.displayText(manifest.description, multiline: true), self.displayText(manifest.changelog ?? "", multiline: true), self.displayText(manifest.author?.name ?? ""), self.displayText(manifest.author?.username ?? ""), manifest.author == nil || !(manifest.author?.name.isEmpty ?? true) else { throw self.error("invalid_manifest", "invalid display metadata") }
        guard self.semver(manifest.version), manifest.apiVersion == "^1.0.0" || manifest.apiVersion == "1.0.0" else { throw self.error("incompatible", "unsupported plugin api version") }
        guard manifest.minClientVersion.range(of: "^[0-9]{1,3}\\.[0-9]{1,3}(\\.[0-9]{1,3})?$", options: .regularExpression) != nil,
              manifest.minClientVersion.compare("13.2.0", options: .numeric) != .orderedDescending else { throw self.error("incompatible", "plugin needs a newer client") }
        guard manifest.profile == "localPrivate" || manifest.profile == "publicNetwork" else { throw self.error("invalid_profile", "unsupported plugin profile") }
        try self.validatePath(manifest.entry)
        guard manifest.entry.hasSuffix(".js") else { throw self.error("invalid_entry", "plugin entry must be javascript source") }
        if let icon = manifest.icon {
            try self.validatePath(icon)
            guard icon.hasPrefix("assets/") else { throw self.error("invalid_icon", "plugin icon must be a local asset") }
        }
        let permissions = manifest.permissions + manifest.optionalPermissions
        guard Set(permissions.map { $0.capability + ":" + $0.scope }).count == permissions.count else { throw self.error("invalid_permissions", "duplicate permission") }
        for permission in permissions { try self.validatePermission(permission, profile: manifest.profile) }
        if let settings = manifest.settingsSchema { try self.validateSettings(settings) }
        return manifest
    }

    private static func validatePermission(_ permission: DGPluginPermission, profile: String) throws {
        let scopes: [String: Set<String>] = [
            "ui.contribute": ["settings", "composer", "selection", "messageMenu", "chatToolbar"],
            "ui.transform": ["profile", "chatList", "displayLinks"],
            "theme.read": ["currentTheme"], "theme.contribute": ["localTokens"],
            "composer.read": ["activeComposer"], "composer.transform": ["activeComposer"],
            "messages.selection.read": ["activeSelection"], "messages.read": ["selectedChats"],
            "chats.metadata.read": ["selectedChats"], "peers.read": ["selectedPeers"],
            "storage.local": ["pluginAccount"], "network.public": ["declaredOrigins"],
            "translation.request": ["selectedText"], "navigation.open": ["safeScreens"],
            "notifications.local": ["pluginAccount"], "files.userSelected": ["selectedFile"],
            "messages.compose": ["chosenRecipient"], "messages.sendInteractive": ["chosenRecipient"]
        ]
        guard scopes[permission.capability]?.contains(permission.scope) == true, (1 ... 512).contains(permission.reason.count), permission.origins.count <= 16, Set(permission.origins).count == permission.origins.count else { throw self.error("invalid_permissions", "invalid capability or scope") }
        let privateCapabilities: Set<String> = ["composer.read", "composer.transform", "messages.selection.read", "messages.read", "chats.metadata.read", "peers.read", "files.userSelected", "messages.compose", "messages.sendInteractive", "translation.request", "ui.transform"]
        if profile == "publicNetwork", privateCapabilities.contains(permission.capability) { throw self.error("invalid_profile", "public-network plugins cannot access private data") }
        if permission.capability == "network.public" {
            guard profile == "publicNetwork", !permission.origins.isEmpty else { throw self.error("invalid_profile", "network access needs publicNetwork profile") }
            for origin in permission.origins { try self.validateOrigin(origin) }
        } else if !permission.origins.isEmpty { throw self.error("invalid_permissions", "origins are only valid for network.public") }
        if profile == "localPrivate", permission.capability == "notifications.local" { throw self.error("invalid_profile", "private plugins cannot export notification payloads") }
    }

    private static func validateOrigin(_ value: String) throws {
        guard let url = URLComponents(string: value), url.scheme == "https", let host = url.host,
              host == host.lowercased(), host.range(of: "^[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\\.[a-z]{2,63}$", options: .regularExpression) != nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil, url.path.isEmpty,
              url.port == nil || url.port == 443, !host.hasSuffix(".localhost"), !host.hasSuffix(".local"), !host.hasSuffix(".internal"),
              value == "https://" + host else { throw self.error("invalid_origin", "network origins must be exact public https origins") }
    }

    private static func validateSettings(_ json: DGPluginJSON) throws {
        guard let object = json.objectValue, object["type"] == .string("object"), let properties = object["properties"]?.objectValue, properties.count <= 32 else { throw self.error("invalid_settings", "invalid settings schema") }
        try self.keys(object, allowed: ["type", "properties"])
        for (key, value) in properties {
            guard key.range(of: "^[A-Za-z][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil, let field = value.objectValue, let type = field["type"]?.stringValue, ["boolean", "string", "number", "integer"].contains(type), let title = field["title"]?.stringValue, (1 ... 128).contains(title.count) else { throw self.error("invalid_settings", "invalid settings field") }
            try self.keys(field, allowed: ["type", "title", "description", "default", "minimum", "maximum", "maxLength", "enum"])
            guard self.displayText(title) else { throw self.error("invalid_settings", "invalid settings title") }
            if let description = field["description"] {
                guard let text = description.stringValue, text.count <= 512, self.displayText(text, multiline: true) else { throw self.error("invalid_settings", "invalid settings description") }
            }
            var minimum: Double?
            var maximum: Double?
            if let value = field["minimum"] {
                guard type == "number" || type == "integer", case let .number(number) = value else { throw self.error("invalid_settings", "invalid settings minimum") }
                minimum = number
            }
            if let value = field["maximum"] {
                guard type == "number" || type == "integer", case let .number(number) = value else { throw self.error("invalid_settings", "invalid settings maximum") }
                maximum = number
            }
            if let minimum, let maximum, minimum > maximum { throw self.error("invalid_settings", "inverted settings bounds") }
            var maxLength = 4096
            if let value = field["maxLength"] {
                guard type == "string", case let .number(number) = value, number.rounded() == number, number >= 1, number <= 4096 else { throw self.error("invalid_settings", "invalid settings length") }
                maxLength = Int(number)
            }
            func validValue(_ value: DGPluginJSON) -> Bool {
                switch (type, value) {
                case ("boolean", .bool): return true
                case ("string", let .string(string)): return string.count <= maxLength
                case ("number", let .number(number)): return number >= (minimum ?? -Double.greatestFiniteMagnitude) && number <= (maximum ?? Double.greatestFiniteMagnitude)
                case ("integer", let .number(number)): return number.rounded() == number && number >= (minimum ?? -Double.greatestFiniteMagnitude) && number <= (maximum ?? Double.greatestFiniteMagnitude)
                default: return false
                }
            }
            var enumValues: [DGPluginJSON]?
            if let value = field["enum"] {
                guard case let .array(values) = value, !values.isEmpty, values.count <= 32, values.allSatisfy(validValue) else { throw self.error("invalid_settings", "invalid settings choices") }
                enumValues = values
            }
            if let defaultValue = field["default"] {
                guard validValue(defaultValue), enumValues?.contains(defaultValue) ?? true else { throw self.error("invalid_settings", "invalid settings default") }
            }
        }
    }

    private static func signature(files: [String: Data], manifest: DGPluginJSON) throws -> (publisher: String, trust: String) {
        guard let data = files["signature.json"] else { return ("unverified", "authorUnverified") }
        guard data.count <= 8192 else { throw self.error("invalid_signature", "invalid signature envelope") }
        var parser = DGStaticJSONParser(data)
        guard let envelope = try parser.complete().objectValue else { throw self.error("invalid_signature", "invalid signature envelope") }
        try self.keys(envelope, allowed: ["algorithm", "publicKey", "signature"])
        guard envelope["algorithm"] == .string("Ed25519"), let keyString = envelope["publicKey"]?.stringValue,
              let keyData = Data(base64Encoded: keyString), keyData.count == 32,
              let signatureString = envelope["signature"]?.stringValue,
              let signature = Data(base64Encoded: signatureString), signature.count == 64 else { throw self.error("invalid_signature", "invalid signature envelope") }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let canonicalManifest = try encoder.encode(manifest)
        var payload = Data("donutgram.plugin.signature.v1\n".utf8)
        for path in files.keys.filter({ $0 != "signature.json" }).sorted() {
            let content = path == "manifest.json" ? canonicalManifest : files[path]!
            payload.append(Data("\(path.utf8.count):\(path):\(self.digest(content))\n".utf8))
        }
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        guard publicKey.isValidSignature(signature, for: payload) else { throw self.error("signature_mismatch", "plugin signature does not match content") }
        return ("ed25519:" + self.digest(keyData), "signatureVerified")
    }

    private static func safeIcon(_ data: Data) -> Data? {
        guard !data.isEmpty, data.count <= 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let type = CGImageSourceGetType(source) as String?, ["public.png", "public.jpeg", "org.webmproject.webp"].contains(type),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.intValue > 0, height.intValue > 0, width.intValue <= 2048, height.intValue <= 2048, width.intValue * height.intValue <= 4 * 1024 * 1024,
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 256, kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    private static func semver(_ value: String) -> Bool {
        guard value.utf8.count <= 64 else { return false }
        guard value.range(of: "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?(?:\\+[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?$", options: .regularExpression) != nil else { return false }
        if let prerelease = value.split(separator: "+", maxSplits: 1).first?.split(separator: "-", maxSplits: 1).dropFirst().first {
            for identifier in prerelease.split(separator: ".") {
                if identifier.allSatisfy({ $0.isNumber }), identifier.count > 1, identifier.first == "0" { return false }
            }
        }
        return true
    }

    private static func displayText(_ value: String, multiline: Bool = false) -> Bool {
        return !value.unicodeScalars.contains(where: { scalar in
            if multiline && (scalar.value == 10 || scalar.value == 13 || scalar.value == 9) { return false }
            return scalar.value < 32 || (127 ... 159).contains(scalar.value) || (0x202a ... 0x202e).contains(scalar.value) || (0x2066 ... 0x2069).contains(scalar.value)
        })
    }

    private static func keys(_ object: [String: DGPluginJSON], allowed: Set<String>) throws {
        guard Set(object.keys).isSubset(of: allowed) else { throw self.error("unknown_field", "unsupported metadata field") }
    }

    private static func error(_ code: String, _ message: String) -> DGPluginError { return DGPluginError(code: code, message: message) }
}
