import Foundation

/// Only message-retention preferences are shared with the notification extension.
/// An extension must not initialize them from its own, unrelated standard defaults.
public final class DGMessagePreservationSettings {
    private let defaults: UserDefaults

    private enum Key {
        static let deleted = "donutgram.spy.saveDeletedMessages"
        static let edits = "donutgram.spy.saveEditHistory"
        static let viewOnce = "donutgram.spy.saveViewOnceMedia"
        static let bots = "donutgram.spy.saveInBotChats"
        static let all = [deleted, edits, viewOnce, bots]
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

    public var saveInBotChats: Bool {
        get { self.defaults.bool(forKey: Key.bots) }
        set { self.set(newValue, forKey: Key.bots) }
    }
}
