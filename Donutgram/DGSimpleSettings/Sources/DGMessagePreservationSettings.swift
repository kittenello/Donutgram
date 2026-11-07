import Foundation

/// Message-retention, banned-chat and mention-notification preferences are shared with the notification extension.
/// An extension must not initialize them from its own, unrelated standard defaults.
public final class DGMessagePreservationSettings {
    private let defaults: UserDefaults

    private enum Key {
        static let deleted = "donutgram.spy.saveDeletedMessages"
        static let edits = "donutgram.spy.saveEditHistory"
        static let viewOnce = "donutgram.spy.saveViewOnceMedia"
        static let bots = "donutgram.spy.saveInBotChats"
        static let removePings = "donutgram.chats.removePings"
        static let own = "donutgram.spy.saveOwnDeletedMessages"
        static let keepBannedChats = "donutgram.general.keepBannedChats"
        static let all = [deleted, edits, viewOnce, bots, removePings, own, keepBannedChats]
    }

    public init(sharedDefaults: UserDefaults, legacyDefaults: UserDefaults, migrateLegacyValues: Bool) {
        self.defaults = sharedDefaults
        if migrateLegacyValues {
            for key in Key.all where sharedDefaults.object(forKey: key) == nil {
                if let value = legacyDefaults.object(forKey: key) {
                    sharedDefaults.set(value, forKey: key)
                }
            }
            // Flush before a separately launched extension reads the preferences.
            sharedDefaults.synchronize()
        }
    }

    private func set(_ value: Bool, forKey key: String) {
        self.defaults.set(value, forKey: key)
        self.defaults.synchronize()
    }

    public var saveDeletedMessages: Bool {
        get { self.defaults.bool(forKey: Key.deleted) }
        set { self.set(newValue, forKey: Key.deleted) }
    }

    public var saveEditHistory: Bool {
        get { self.defaults.bool(forKey: Key.edits) }
        set { self.set(newValue, forKey: Key.edits) }
    }

    public var saveViewOnceMedia: Bool {
        get { self.defaults.bool(forKey: Key.viewOnce) }
        set { self.set(newValue, forKey: Key.viewOnce) }
    }

    public var removePings: Bool {
        get { self.defaults.bool(forKey: Key.removePings) }
        set { self.set(newValue, forKey: Key.removePings) }
    }

    public var saveInBotChats: Bool {
        get { self.defaults.bool(forKey: Key.bots) }
        set { self.set(newValue, forKey: Key.bots) }
    }

    /// On until switched off: an extension can run before the app has written the preference.
    public var saveOwnDeletedMessages: Bool {
        get { (self.defaults.object(forKey: Key.own) as? Bool) ?? true }
        set { self.set(newValue, forKey: Key.own) }
    }

    /// The extension applies the update that bans the account from a chat as often as the app does, and a chat it lets
    /// go is not kept later: by then the stored membership is already the banned one.
    public var keepBannedChats: Bool {
        get { self.defaults.bool(forKey: Key.keepBannedChats) }
        set { self.set(newValue, forKey: Key.keepBannedChats) }
    }
}
