import Foundation

public extension DGSimpleSettings {
    /// Display-only normalization. Call this for known admins/owners, leaving the server's title untouched.
    func visibleAdminTitle(_ title: String?) -> String? {
        guard self.showInvisibleAdmins, let title else {
            return title
        }
        let hasVisibleContent = title.unicodeScalars.contains { scalar in
            return !CharacterSet.whitespacesAndNewlines.contains(scalar)
                && !CharacterSet.controlCharacters.contains(scalar)
                && !scalar.properties.isDefaultIgnorableCodePoint
                && scalar.value != 0x2800 // Braille blank is not Unicode whitespace.
        }
        return hasVisibleContent ? title : nil
    }
}
