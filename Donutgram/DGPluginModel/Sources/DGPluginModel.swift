import Foundation

public indirect enum DGPluginJSON: Codable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([DGPluginJSON])
    case object([String: DGPluginJSON])

    public init(from decoder: Decoder) throws {
        guard decoder.codingPath.count <= 64 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "plugin json exceeds nesting limit"))
        }
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self), value.isFinite { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([DGPluginJSON].self) { self = .array(value) }
        else { self = .object(try container.decode([String: DGPluginJSON].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }

    public var objectValue: [String: DGPluginJSON]? {
        if case let .object(value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        if case let .string(value) = self { return value }
        return nil
    }

    public func validateLimits(maximumDepth: Int = 24, maximumNodes: Int = 8192) throws {
        var pending: [(DGPluginJSON, Int)] = [(self, 0)]
        var nodes = 0
        while let (value, depth) = pending.popLast() {
            nodes += 1
            guard depth <= maximumDepth, nodes <= maximumNodes else { throw DGPluginError(code: "quota_exceeded", message: "plugin json exceeds structural limits") }
            switch value {
            case let .array(values):
                guard values.count <= maximumNodes - nodes - pending.count else { throw DGPluginError(code: "quota_exceeded", message: "plugin json exceeds structural limits") }
                pending.append(contentsOf: values.map { ($0, depth + 1) })
            case let .object(values):
                guard values.count <= maximumNodes - nodes - pending.count else { throw DGPluginError(code: "quota_exceeded", message: "plugin json exceeds structural limits") }
                pending.append(contentsOf: values.values.map { ($0, depth + 1) })
            case let .number(number):
                guard number.isFinite else { throw DGPluginError(code: "invalid_argument", message: "plugin json contains a non-finite number") }
            default: break
            }
        }
    }
}

public struct DGPluginError: Error, LocalizedError, Equatable {
    public let code: String
    public let message: String
    public var errorDescription: String? { return self.message }
    public init(code: String, message: String) { self.code = code; self.message = message }
}

public struct DGPluginPermission: Codable, Hashable {
    public let capability: String
    public let scope: String
    public let reason: String
    public let origins: [String]
    public init(capability: String, scope: String, reason: String, origins: [String] = []) {
        self.capability = capability; self.scope = scope; self.reason = reason; self.origins = origins
    }
    private enum CodingKeys: String, CodingKey { case capability, scope, reason, origins }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.capability = try values.decode(String.self, forKey: .capability)
        self.scope = try values.decode(String.self, forKey: .scope)
        self.reason = try values.decode(String.self, forKey: .reason)
        self.origins = try values.decodeIfPresent([String].self, forKey: .origins) ?? []
    }
}

public struct DGPluginAuthor: Codable, Equatable {
    public let name: String
    public let username: String?
    public init(name: String, username: String? = nil) { self.name = name; self.username = username }
}

public struct DGPluginManifest: Codable, Equatable {
    public let kind: String
    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let version: String
    public let description: String
    public let author: DGPluginAuthor?
    public let apiVersion: String
    public let minClientVersion: String
    public let entry: String
    public let icon: String?
    public let permissions: [DGPluginPermission]
    public let optionalPermissions: [DGPluginPermission]
    public let settingsSchema: DGPluginJSON?
    public let profile: String
    public let changelog: String?

    public init(kind: String = "donutgram.plugin", schemaVersion: Int = 1, id: String, name: String, version: String, description: String, author: DGPluginAuthor? = nil, apiVersion: String = "^1.0.0", minClientVersion: String = "13.2", entry: String = "main.js", icon: String? = nil, permissions: [DGPluginPermission] = [], optionalPermissions: [DGPluginPermission] = [], settingsSchema: DGPluginJSON? = nil, profile: String = "localPrivate", changelog: String? = nil) {
        self.kind = kind; self.schemaVersion = schemaVersion; self.id = id; self.name = name
        self.version = version; self.description = description; self.author = author; self.apiVersion = apiVersion
        self.minClientVersion = minClientVersion; self.entry = entry; self.icon = icon; self.permissions = permissions
        self.optionalPermissions = optionalPermissions; self.settingsSchema = settingsSchema; self.profile = profile; self.changelog = changelog
    }

    private enum CodingKeys: String, CodingKey {
        case kind, schemaVersion, id, name, version, description, author, apiVersion, minClientVersion, entry, icon, permissions, optionalPermissions, settingsSchema, profile, changelog
    }

    public init(from decoder: Decoder) throws {
        let v = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try v.decode(String.self, forKey: .kind)
        self.schemaVersion = try v.decode(Int.self, forKey: .schemaVersion)
        self.id = try v.decode(String.self, forKey: .id)
        self.name = try v.decode(String.self, forKey: .name)
        self.version = try v.decode(String.self, forKey: .version)
        self.description = try v.decode(String.self, forKey: .description)
        self.author = try v.decodeIfPresent(DGPluginAuthor.self, forKey: .author)
        self.apiVersion = try v.decode(String.self, forKey: .apiVersion)
        self.minClientVersion = try v.decodeIfPresent(String.self, forKey: .minClientVersion) ?? "13.2"
        self.entry = try v.decodeIfPresent(String.self, forKey: .entry) ?? "main.js"
        self.icon = try v.decodeIfPresent(String.self, forKey: .icon)
        self.permissions = try v.decode([DGPluginPermission].self, forKey: .permissions)
        self.optionalPermissions = try v.decodeIfPresent([DGPluginPermission].self, forKey: .optionalPermissions) ?? []
        self.settingsSchema = try v.decodeIfPresent(DGPluginJSON.self, forKey: .settingsSchema)
        self.profile = try v.decodeIfPresent(String.self, forKey: .profile) ?? "localPrivate"
        self.changelog = try v.decodeIfPresent(String.self, forKey: .changelog)
    }
}

public enum DGPluginState: String, Codable {
    case discovered, validated, installedDisabled, starting, running, stopping, incompatible, permissionRequired, updating, quarantined, failed, removing, removed
}

public struct DGPluginInstallation: Codable, Equatable {
    public var id: String
    public var manifest: DGPluginManifest
    public var digest: String
    public var trust: String
    public var enabled: Bool
    public var state: DGPluginState
    public var grants: [DGPluginPermission]
    public var settings: [String: DGPluginJSON]
    public var lastError: String?
    public init(id: String, manifest: DGPluginManifest, digest: String, trust: String, enabled: Bool = false, state: DGPluginState = .installedDisabled, grants: [DGPluginPermission] = [], settings: [String: DGPluginJSON] = [:], lastError: String? = nil) {
        self.id = id; self.manifest = manifest; self.digest = digest; self.trust = trust; self.enabled = enabled
        self.state = state; self.grants = grants; self.settings = settings; self.lastError = lastError
    }
}

public struct DGPluginCommandDescriptor: Codable, Equatable {
    public let installationId: String
    public let id: String
    public let title: String
    public let placement: String
    public init(installationId: String, id: String, title: String, placement: String) {
        self.installationId = installationId; self.id = id; self.title = title; self.placement = placement
    }
}
