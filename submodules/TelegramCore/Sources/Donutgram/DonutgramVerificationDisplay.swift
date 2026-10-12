import DGSimpleSettings

/// Filters Telegram verification for presentation without changing server peer data or trust checks.
/// Donutgram team badges are rendered separately and must not pass through this filter.
public enum DonutgramVerificationDisplay {
    public static var isHidden: Bool {
        return DGSimpleSettings.shared.hideVerification
    }

    public static func isVerified(_ value: Bool) -> Bool {
        return value && !self.isHidden
    }

    public static func iconFileId(_ value: Int64?) -> Int64? {
        return self.isHidden ? nil : value
    }

    public static func verification(_ value: PeerVerification?) -> PeerVerification? {
        return self.isHidden ? nil : value
    }
}
