import Foundation

public extension DGSimpleSettings {
    /// Display-only normalization. Call this for known admins/owners, leaving the server's title untouched.
    func visibleAdminTitle(_ title: String?) -> String? {
        guard self.showInvisibleAdmins, let title else {
            return title
        }
        let hasVisibleContent = title.precomposedStringWithCompatibilityMapping.unicodeScalars.contains { scalar in
            return !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && scalar.properties.generalCategory != .control
                && !scalar.properties.isDefaultIgnorableCodePoint
                && scalar.value != 0x2800
                && scalar.value != 0x1d159
                && scalar.value != 0xfffc
        }
        return hasVisibleContent ? title : nil
    }
}
