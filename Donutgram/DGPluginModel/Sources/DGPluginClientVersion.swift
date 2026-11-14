import Foundation

/// The running app's version for plugin compatibility: a manifest's `minClientVersion` and the `clientVersion` the
/// environment reports. It is read from the bundle (`CFBundleShortVersionString`, set from versions.json), so it follows
/// every upstream update instead of a constant. A host without a bundle version (the portable tests) uses 13.2.
public enum DGPluginClientVersion {
    public static let fallback = "13.2"

    public static let current: String = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String, valid(value) {
            return value
        }
        return fallback
    }()

    /// Whether a plugin that needs `minimum` ("13.2" or "13.2.1") can run on this version.
    public static func satisfies(_ minimum: String) -> Bool {
        guard valid(minimum) else { return false }
        return !components(current).lexicographicallyPrecedes(components(minimum))
    }

    public static func valid(_ value: String) -> Bool {
        return value.range(of: "^[0-9]{1,3}\\.[0-9]{1,3}(\\.[0-9]{1,3})?$", options: .regularExpression) != nil
    }

    private static func components(_ value: String) -> [Int] {
        var parts = value.split(separator: ".").map { Int($0) ?? 0 }
        while parts.count < 3 { parts.append(0) }
        return parts
    }
}
