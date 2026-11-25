import Foundation

public struct DGPluginSemanticVersion: Comparable {
    private let components: [String]
    private let prerelease: [String]

    public init?(_ value: String) {
        guard value.utf8.count <= 64, value.range(of: "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?(?:\\+[0-9A-Za-z-]+(?:\\.[0-9A-Za-z-]+)*)?$", options: .regularExpression) != nil else { return nil }
        let core = value.split(separator: "+", maxSplits: 1)[0].split(separator: "-", maxSplits: 1)
        self.components = core[0].split(separator: ".").map(String.init)
        self.prerelease = core.count == 2 ? core[1].split(separator: ".").map(String.init) : []
        guard !prerelease.contains(where: { Self.numeric($0) && $0.count > 1 && $0.first == "0" }) else { return nil }
    }

    private static func numeric(_ value: String) -> Bool { return value.utf8.allSatisfy { $0 >= 48 && $0 <= 57 } }

    private static func numberLess(_ lhs: String, _ rhs: String) -> Bool {
        return lhs.count == rhs.count ? lhs < rhs : lhs.count < rhs.count
    }

    public static func == (lhs: DGPluginSemanticVersion, rhs: DGPluginSemanticVersion) -> Bool {
        return lhs.components == rhs.components && lhs.prerelease == rhs.prerelease
    }

    public static func < (lhs: DGPluginSemanticVersion, rhs: DGPluginSemanticVersion) -> Bool {
        for (left, right) in zip(lhs.components, rhs.components) where left != right { return Self.numberLess(left, right) }
        if lhs.prerelease.isEmpty { return false }
        if rhs.prerelease.isEmpty { return true }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            let leftNumeric = Self.numeric(left), rightNumeric = Self.numeric(right)
            if leftNumeric != rightNumeric { return leftNumeric }
            return leftNumeric ? Self.numberLess(left, right) : left < right
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
