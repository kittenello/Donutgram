import Foundation

public struct DGVisualUsername: Codable, Equatable {
    public var name: String
    public var isActive: Bool
    public var addedAt: Int32
    public var tonPrice: Int64

    public init(name: String, isActive: Bool, addedAt: Int32 = Int32(Date().timeIntervalSince1970), tonPrice: Int64 = Int64.random(in: 9 ... 90)) {
        self.name = name
        self.isActive = isActive
        self.addedAt = addedAt
        self.tonPrice = tonPrice
    }

    private enum CodingKeys: String, CodingKey { case name, isActive, addedAt, tonPrice }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.isActive = try container.decode(Bool.self, forKey: .isActive)
        self.addedAt = try container.decodeIfPresent(Int32.self, forKey: .addedAt) ?? Int32(Date().timeIntervalSince1970)
        self.tonPrice = try container.decodeIfPresent(Int64.self, forKey: .tonPrice) ?? 9
    }
}

/// One snapshot shared by the real tab bar and its settings preview.
public struct DGTabBarLayout: Equatable {
    public let hidden: Bool
    public let contacts: Bool
    public let calls: Bool
    public let wide: Bool
    public let integratedSearch: Bool
    public let searchOnLeft: Bool

    public init(hidden: Bool, contacts: Bool, calls: Bool, wide: Bool, integratedSearch: Bool, searchOnLeft: Bool) {
        self.hidden = hidden
        self.contacts = contacts
        self.calls = calls
        self.wide = wide
        self.integratedSearch = integratedSearch
        self.searchOnLeft = searchOnLeft
    }
}

public final class DGSimpleSettings {
    public static let shared = DGSimpleSettings()
    public static let didChangeNotification = Notification.Name("donutgram.settings.didChange")
    public static let requestOfflineNotification = Notification.Name("donutgram.ghost.requestOffline")
    /// `requestOfflineNotification` user info: the `PeerId.toInt64()` of the account to send the offline packet for.
    public static let requestOfflineAccountPeerIdKey = "accountPeerId"
    public static let lastOnlineDidChangeNotification = Notification.Name("donutgram.presence.lastOnlineDidChange")
    /// The shadow ban list or a chat's «Показать скрытые» changed. Separate from didChangeNotification, which makes presence
    /// send account.updateStatus.
    public static let shadowBanDidChangeNotification = Notification.Name("donutgram.shadowBan.didChange")

    public enum TranscriptionBackend: String, CaseIterable {
        case telegram
        case apple
        /// Telegram while it can transcribe a message itself, Apple otherwise.
        case auto
    }

    public enum RoundVideoCamera: Int, CaseIterable {
        case front = 0
        case rear = 1
        case ask = 2
    }

    public enum ChannelBottomButton: Int, CaseIterable {
        case discuss = 0
        case mute = 1
        case hidden = 2
    }

    public struct MusicPlaybackExceptions: OptionSet {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let roundVideos = MusicPlaybackExceptions(rawValue: 1 << 0)
        public static let voiceRecording = MusicPlaybackExceptions(rawValue: 1 << 1)
        public static let voicePlayback = MusicPlaybackExceptions(rawValue: 1 << 2)
    }

    public enum DialogIdFormat: Int {
        case telegramApi = 0
        case botApi = 1
    }

    public enum ChatListTitleMode: Int, CaseIterable {
        case chats = 0
        case donutgram = 1
        case username = 2
        case nickname = 3
    }

    private enum Key {
        static let wideChannelPosts = "donutgram.channels.widePosts"
        static let channelBottomButton = "donutgram.channels.bottomButton"
        static let saveDeletedMessages = "donutgram.spy.saveDeletedMessages"
        static let semiTransparentDeletedMessages = "donutgram.spy.semiTransparentDeletedMessages"
        static let saveEditHistory = "donutgram.spy.saveEditHistory"
        static let saveViewOnceMedia = "donutgram.spy.saveViewOnceMedia"
        static let saveProtectedStories = "donutgram.spy.saveProtectedStories"
        static let gifUnlock = "donutgram.general.gifUnlock"
        static let saveInBotChats = "donutgram.spy.saveInBotChats"
        static let showDisappearedGifts = "donutgram.spy.showDisappearedGifts"

        static let ghostModeEnabled = "donutgram.ghost.enabled"
        static let ghostReadMessages = "donutgram.ghost.readMessages"
        static let ghostReadStories = "donutgram.ghost.readStories"
        static let ghostSendOnline = "donutgram.ghost.sendOnline"
        static let ghostSendTyping = "donutgram.ghost.sendTyping"
        static let ghostAutomaticOffline = "donutgram.ghost.automaticOffline"
        static let ghostReadOnAction = "donutgram.ghost.readOnAction"
        static let ghostUseScheduledMessages = "donutgram.ghost.useScheduledMessages"
        static let ghostSendWithoutSound = "donutgram.ghost.sendWithoutSound"
        static let ghostSuggestForStories = "donutgram.ghost.suggestForStories"
        static let bypassForwardRestrictions = "donutgram.spy.bypassForwardRestrictions"
        static let visualPhoneEnabled = "donutgram.profile.visualPhoneEnabled"
        static let visualPhoneNumber = "donutgram.profile.visualPhoneNumber"

        static let hideTabBar = "donutgram.appearance.hideTabBar"
        static let showContactsTab = "donutgram.appearance.showContactsTab"
        static let showCallsTab = "donutgram.appearance.showCallsTab"
        static let wideTabBar = "donutgram.appearance.wideTabBar"
        static let integratedTabSearch = "donutgram.appearance.integratedTabSearch"
        static let tabSearchOnLeft = "donutgram.appearance.tabSearchOnLeft"
        static let showProfileId = "donutgram.appearance.showProfileId"
        static let dialogIdFormat = "donutgram.appearance.dialogIdFormat"
        static let relativeOnlineTime = "donutgram.appearance.relativeOnlineTime"
        static let hidePhoneNumber = "donutgram.appearance.hidePhoneNumber"
        static let showDc = "donutgram.appearance.showDc"
        static let showRegistrationDate = "donutgram.appearance.showRegistrationDate"
        static let showChatCreationDate = "donutgram.appearance.showChatCreationDate"
        static let showMutualContact = "donutgram.appearance.showMutualContact"
        static let confirmCalls = "donutgram.appearance.confirmCalls"
        static let disableAds = "donutgram.appearance.disableAds"
        static let hidePremiumStatuses = "donutgram.appearance.hidePremiumStatuses"
        static let disableCustomBackgrounds = "donutgram.appearance.disableCustomBackgrounds"
        static let hideStories = "donutgram.appearance.hideStories"
        static let forceSnow = "donutgram.appearance.forceSnow"
        static let chatListHideStatus = "donutgram.chats.appearance.hideStatus"
        static let chatListHideEmojiStatus = "donutgram.chats.appearance.hideEmojiStatus"
        static let chatListCenteredTitle = "donutgram.chats.appearance.centeredTitle"
        static let chatListHideSearch = "donutgram.chats.appearance.hideSearch"
        static let chatListFoldersAtBottom = "donutgram.chats.appearance.foldersAtBottom"
        static let chatListTitleMode = "donutgram.chats.appearance.titleMode"
        static let islandStyle = "donutgram.appearance.islandStyle"
        static let islandFollowsIcon = "donutgram.appearance.islandFollowsIcon"
        static let pickedAppIconName = "donutgram.appearance.pickedAppIconName"
        static let localPremiumPeerIds = "donutgram.other.localPremiumPeerIds"
        static let shadowBannedPeerIds = "donutgram.spy.shadowBannedPeerIds"

        static let onlyAddedStickers = "donutgram.chats.onlyAddedStickers"
        static let infiniteRecentStickers = "donutgram.chats.infiniteRecentStickers"
        static let hidePaidReactions = "donutgram.chats.hidePaidReactions"
        static let hideBirthdayNotifications = "donutgram.appearance.hideBirthdayNotifications"
        static let hideViaBot = "donutgram.chats.hideViaBot"
        static let showPinnedMessagesWithBot = "donutgram.chats.showPinnedMessagesWithBot"
        static let hideBotAutomation = "donutgram.chats.hideBotAutomation"
        static let removeLinkPreviews = "donutgram.chats.removeLinkPreviews"
        static let autoplayMedia = "donutgram.chats.autoplayMedia"
        static let autoplayMediaTypes = "donutgram.chats.autoplayMediaTypes"
        static let hiddenReactions = "donutgram.chats.hiddenReactions"
        static let removeMessageTails = "donutgram.chats.removeMessageTails"
        static let hideShareButton = "donutgram.chats.hideShareButton"
        static let disableColoredReplies = "donutgram.chats.disableColoredReplies"
        static let showMessageSeconds = "donutgram.chats.showMessageSeconds"
        static let showForwardDate = "donutgram.chats.showForwardDate"
        static let transcriptionBackend = "donutgram.chats.transcriptionBackend"
        static let downloadTikTok = "donutgram.chats.downloadTikTok"
        static let downloadYouTubeShorts = "donutgram.chats.downloadYouTubeShorts"
        static let signDownloadedMedia = "donutgram.chats.signDownloadedMedia"
        static let forceBuiltInMicrophone = "donutgram.chats.forceBuiltInMicrophone"
        static let startRoundVideoWithRearCamera = "donutgram.chats.startRoundVideoWithRearCamera"
        static let roundVideoCamera = "donutgram.chats.roundVideoCamera"
        static let musicPlaybackExceptions = "donutgram.chats.musicPlaybackExceptions"
        static let rememberRoundVideoCamera = "donutgram.chats.rememberRoundVideoCamera"
        static let lastRoundVideoCamera = "donutgram.chats.lastRoundVideoCamera"
        static let roundVideoZoomSlider = "donutgram.chats.roundVideoZoomSlider"
        static let staticRoundVideoZoom = "donutgram.chats.staticRoundVideoZoom"
        static let autoPause = "donutgram.chats.autoPause"
        static let doubleTapSeekSeconds = "donutgram.chats.doubleTapSeekSeconds"
        static let showPollResultsBeforeVoting = "donutgram.chats.showPollResultsBeforeVoting"
        static let showChannelForwardCount = "donutgram.chats.showChannelForwardCount"
        static let autoPauseMedia = "donutgram.chats.autoPauseMedia"
        static let editedIcon = "donutgram.chats.editedIcon"
        static let showOnlineIndicator = "donutgram.chats.showOnlineIndicator"
        static let hideGreetingSticker = "donutgram.chats.hideGreetingSticker"
        static let commaAfterMention = "donutgram.chats.commaAfterMention"
        static let mentionAvatars = "donutgram.chats.mentionAvatars"
        static let hideArchive = "donutgram.chats.hideArchive"
        static let openArchiveOnPull = "donutgram.chats.openArchiveOnPull"
        static let downloadAcceleration = "donutgram.network.downloadAcceleration"
        static let accelerateUpload = "donutgram.network.accelerateUpload"
    }

    private let defaults: UserDefaults
    private var preservationSettings: DGMessagePreservationSettings?

    public func configureMessagePreservation(appGroupName: String, isMainApp: Bool) {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupName) else {
            return
        }
        self.preservationSettings = DGMessagePreservationSettings(
            sharedDefaults: sharedDefaults,
            legacyDefaults: self.defaults,
            migrateLegacyValues: isMainApp
        )
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: Key.saveDeletedMessages) == nil {
            defaults.set(true, forKey: Key.saveDeletedMessages)
        }
        if defaults.object(forKey: Key.semiTransparentDeletedMessages) == nil {
            defaults.set(false, forKey: Key.semiTransparentDeletedMessages)
        }
        if defaults.object(forKey: Key.saveEditHistory) == nil {
            defaults.set(true, forKey: Key.saveEditHistory)
        }
        if defaults.object(forKey: Key.saveViewOnceMedia) == nil {
            defaults.set(false, forKey: Key.saveViewOnceMedia)
        }
        if defaults.object(forKey: Key.saveInBotChats) == nil {
            defaults.set(false, forKey: Key.saveInBotChats)
        }
        let enabledByDefault = [Key.ghostReadMessages, Key.ghostReadStories, Key.ghostSendOnline, Key.ghostSendTyping, Key.showContactsTab, Key.showCallsTab, Key.showProfileId]
        for key in enabledByDefault where defaults.object(forKey: key) == nil {
            defaults.set(true, forKey: key)
        }
    }

    public var saveDeletedMessages: Bool {
        get {
            return self.preservationSettings?.saveDeletedMessages ?? self.defaults.bool(forKey: Key.saveDeletedMessages)
        }
        set {
            self.defaults.set(newValue, forKey: Key.saveDeletedMessages)
            self.preservationSettings?.saveDeletedMessages = newValue
        }
    }

    public var semiTransparentDeletedMessages: Bool {
        get {
            return self.defaults.bool(forKey: Key.semiTransparentDeletedMessages)
        }
        set {
            self.defaults.set(newValue, forKey: Key.semiTransparentDeletedMessages)
        }
    }

    public var saveEditHistory: Bool {
        get {
            return self.preservationSettings?.saveEditHistory ?? self.defaults.bool(forKey: Key.saveEditHistory)
        }
        set {
            self.defaults.set(newValue, forKey: Key.saveEditHistory)
            self.preservationSettings?.saveEditHistory = newValue
        }
    }

    public var saveViewOnceMedia: Bool {
        get {
            return self.preservationSettings?.saveViewOnceMedia ?? self.defaults.bool(forKey: Key.saveViewOnceMedia)
        }
        set {
            self.defaults.set(newValue, forKey: Key.saveViewOnceMedia)
            self.preservationSettings?.saveViewOnceMedia = newValue
        }
    }

    public var saveInBotChats: Bool {
        get {
            return self.preservationSettings?.saveInBotChats ?? self.defaults.bool(forKey: Key.saveInBotChats)
        }
        set {
            self.defaults.set(newValue, forKey: Key.saveInBotChats)
            self.preservationSettings?.saveInBotChats = newValue
        }
    }

    public var showDisappearedGifts: Bool {
        get { bool(Key.showDisappearedGifts) }
        set { setBool(newValue, Key.showDisappearedGifts) }
    }

    public var saveProtectedStories: Bool {
        get { bool(Key.saveProtectedStories) }
        set { setBool(newValue, Key.saveProtectedStories) }
    }

    public var avatarGlow: Bool {
        get { bool("donutgram.appearance.avatarGlow") }
        set { setBool(newValue, "donutgram.appearance.avatarGlow") }
    }
    public var reactionGlow: Bool {
        get { bool("donutgram.appearance.reactionGlow") }
        set { setBool(newValue, "donutgram.appearance.reactionGlow") }
    }

    private func bool(_ key: String) -> Bool { self.defaults.bool(forKey: key) }
    private func setBool(_ value: Bool, _ key: String) {
        if self.defaults.object(forKey: key) != nil && self.defaults.bool(forKey: key) == value {
            return
        }
        self.defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: DGSimpleSettings.didChangeNotification, object: self)
    }
    private func integer(_ key: String) -> Int { self.defaults.integer(forKey: key) }
    private func setInteger(_ value: Int, _ key: String) {
        if self.defaults.object(forKey: key) != nil && self.defaults.integer(forKey: key) == value { return }
        self.defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: DGSimpleSettings.didChangeNotification, object: self)
    }
    private func string(_ key: String) -> String { self.defaults.string(forKey: key) ?? "" }
    private func setString(_ value: String, _ key: String) {
        if self.defaults.string(forKey: key) == value { return }
        self.defaults.set(value, forKey: key)
        NotificationCenter.default.post(name: DGSimpleSettings.didChangeNotification, object: self)
    }

    /// Asks for an offline packet after an action that shows the user online on the server, for the
    /// account with `accountPeerId` (`PeerId.toInt64()`) or for every account when it is nil.
    public func requestGhostOffline(accountPeerId: Int64? = nil) {
        guard self.ghostModeEnabled && self.ghostAutomaticOffline else { return }
        var userInfo: [AnyHashable: Any]?
        if let accountPeerId {
            userInfo = [DGSimpleSettings.requestOfflineAccountPeerIdKey: accountPeerId]
        }
        NotificationCenter.default.post(name: DGSimpleSettings.requestOfflineNotification, object: self, userInfo: userInfo)
    }

    public var ghostModeEnabled: Bool {
        get {
            return bool(Key.ghostModeEnabled)
        }
        set {
            // Match AyuGram's master toggle: enabling ghost mode immediately
            // enables every privacy guard unless the user changes it afterwards.
            // This also makes upgrading from the old permissive defaults safe.
            ghostReadMessages = !newValue
            ghostReadStories = !newValue
            ghostSendOnline = !newValue
            ghostSendTyping = !newValue
            ghostAutomaticOffline = newValue
            setBool(newValue, Key.ghostModeEnabled)
        }
    }
    public var ghostReadMessages: Bool { get { bool(Key.ghostReadMessages) } set { setBool(newValue, Key.ghostReadMessages) } }
    public var ghostReadStories: Bool { get { bool(Key.ghostReadStories) } set { setBool(newValue, Key.ghostReadStories) } }
    public var ghostSendOnline: Bool { get { bool(Key.ghostSendOnline) } set { setBool(newValue, Key.ghostSendOnline) } }
    public var ghostSendTyping: Bool { get { bool(Key.ghostSendTyping) } set { setBool(newValue, Key.ghostSendTyping) } }
    public var ghostAutomaticOffline: Bool { get { bool(Key.ghostAutomaticOffline) } set { setBool(newValue, Key.ghostAutomaticOffline) } }
    public var ghostHidesOnline: Bool {
        return ghostModeEnabled && (!ghostSendOnline || ghostAutomaticOffline)
    }
    public var ghostReadOnAction: Bool { get { bool(Key.ghostReadOnAction) } set { setBool(newValue, Key.ghostReadOnAction) } }
    public var ghostUseScheduledMessages: Bool { get { bool(Key.ghostUseScheduledMessages) } set { setBool(newValue, Key.ghostUseScheduledMessages) } }
    public var ghostSendWithoutSound: Int { get { integer(Key.ghostSendWithoutSound) } set { setInteger(newValue, Key.ghostSendWithoutSound) } }
    public var ghostSuggestForStories: Bool { get { bool(Key.ghostSuggestForStories) } set { setBool(newValue, Key.ghostSuggestForStories) } }
    public var bypassForwardRestrictions: Bool { get { bool(Key.bypassForwardRestrictions) } set { setBool(newValue, Key.bypassForwardRestrictions) } }
    public var visualPhoneEnabled: Bool { get { bool(Key.visualPhoneEnabled) } set { setBool(newValue, Key.visualPhoneEnabled) } }
    public var visualPhoneNumber: String { get { string(Key.visualPhoneNumber) } set { setString(newValue, Key.visualPhoneNumber) } }

    private func accountKey(_ suffix: String, accountId: Int64) -> String {
        return "donutgram.profile.\(accountId).\(suffix)"
    }

    public var stickerSize: Int {
        get {
            let key = "donutgram.chats.stickers.size"
            return defaults.object(forKey: key) == nil ? 11 : min(20, max(1, integer(key)))
        }
        set { setInteger(min(20, max(1, newValue)), "donutgram.chats.stickers.size") }
    }
    public var stickerScale: Double {
        let size = Double(stickerSize)
        return size <= 11 ? 0.25 + (size - 1) * 0.075 : 1.0 + (size - 11) / 12.0
    }
    public var hideStickerTime: Bool {
        get { bool("donutgram.chats.stickers.hideTime") }
        set { setBool(newValue, "donutgram.chats.stickers.hideTime") }
    }
    // Reply decorations: colors = 1, emoji pattern = 2, background = 4.
    public var stickerReplyOptions: Int {
        get {
            let key = "donutgram.chats.stickers.replyOptions"
            return defaults.object(forKey: key) == nil ? 7 : integer(key) & 7
        }
        set { setInteger(newValue & 7, "donutgram.chats.stickers.replyOptions") }
    }
    public var stickerShape: Int {
        get { min(2, max(0, integer("donutgram.chats.stickers.shape"))) }
        set { setInteger(min(2, max(0, newValue)), "donutgram.chats.stickers.shape") }
    }
    public var stickerCornerRadius: Double {
        switch stickerShape {
        case 1: return 12.0
        case 2: return 22.0
        default: return 0.0
        }
    }
    public var hideStickerChecks: Bool {
        get { bool("donutgram.chats.stickers.hideChecks") }
        set { setBool(newValue, "donutgram.chats.stickers.hideChecks") }
    }

    public func lastOnlineTimestamp(accountId: Int64) -> Int32? {
        let value = integer(accountKey("lastOnlineTimestamp", accountId: accountId))
        guard value > 0, let timestamp = Int32(exactly: value) else { return nil }
        return timestamp
    }

    public func setLastOnlineTimestamp(_ timestamp: Int32, accountId: Int64) {
        let key = accountKey("lastOnlineTimestamp", accountId: accountId)
        guard timestamp > 0, integer(key) != Int(timestamp) else { return }
        self.defaults.set(Int(timestamp), forKey: key)
        // Presence updates must not trigger another account.updateStatus request.
        NotificationCenter.default.post(name: DGSimpleSettings.lastOnlineDidChangeNotification, object: self)
    }

    public func visualProfileId(accountId: Int64) -> String {
        return string(accountKey("visualProfileId", accountId: accountId))
    }

    public func setVisualProfileId(_ value: String, accountId: Int64) {
        setString(value.trimmingCharacters(in: .whitespacesAndNewlines), accountKey("visualProfileId", accountId: accountId))
    }

    public func visualRatingLevel(accountId: Int64) -> Int? {
        let key = accountKey("visualRatingLevel", accountId: accountId)
        guard self.defaults.object(forKey: key) != nil else { return nil }
        let level = self.defaults.integer(forKey: key)
        return (1 ... 100).contains(level) ? level : nil
    }

    public func setVisualRatingLevel(_ level: Int?, accountId: Int64) {
        let key = accountKey("visualRatingLevel", accountId: accountId)
        if let level, (1 ... 100).contains(level) {
            self.defaults.set(level, forKey: key)
        } else {
            self.defaults.removeObject(forKey: key)
        }
        NotificationCenter.default.post(name: DGSimpleSettings.didChangeNotification, object: self)
    }

    public func visualUsernames(accountId: Int64) -> [DGVisualUsername] {
        let key = accountKey("visualUsernames", accountId: accountId)
        guard let data = self.defaults.data(forKey: key),
              let result = try? JSONDecoder().decode([DGVisualUsername].self, from: data) else { return [] }
        return result
    }

    public func setVisualUsernames(_ usernames: [DGVisualUsername], accountId: Int64) {
        guard let data = try? JSONEncoder().encode(usernames) else { return }
        self.defaults.set(data, forKey: accountKey("visualUsernames", accountId: accountId))
        NotificationCenter.default.post(name: DGSimpleSettings.didChangeNotification, object: self)
    }

    public func updateVisualUsernames(_ text: String, accountId: Int64) {
        let previous = visualUsernames(accountId: accountId)
        var result: [DGVisualUsername] = []
        var seen = Set<String>()
        for part in text.components(separatedBy: CharacterSet(charactersIn: ",\n")) {
            let name = part.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            let key = name.lowercased()
            guard !name.isEmpty, name.range(of: "^[A-Za-z][A-Za-z0-9_]{4,31}$", options: .regularExpression) != nil, seen.insert(key).inserted else { continue }
            if var existing = previous.first(where: { $0.name.lowercased() == key }) {
                existing.name = name
                result.append(existing)
            } else {
                result.append(DGVisualUsername(name: name, isActive: true))
            }
        }
        setVisualUsernames(result, accountId: accountId)
    }

    public func setVisualUsernameActive(_ name: String, isActive: Bool, accountId: Int64) {
        var usernames = visualUsernames(accountId: accountId)
        guard let index = usernames.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        usernames[index].isActive = isActive
        setVisualUsernames(usernames, accountId: accountId)
    }

    public func visualUsernameOrder(accountId: Int64) -> [String] {
        return self.defaults.stringArray(forKey: accountKey("visualUsernameOrder", accountId: accountId)) ?? []
    }

    public func setVisualUsernameOrder(_ order: [String], accountId: Int64) {
        self.defaults.set(order, forKey: accountKey("visualUsernameOrder", accountId: accountId))
        NotificationCenter.default.post(name: DGSimpleSettings.didChangeNotification, object: self)
    }

    public var hideTabBar: Bool { get { bool(Key.hideTabBar) } set { setBool(newValue, Key.hideTabBar) } }
    public var showContactsTab: Bool { get { bool(Key.showContactsTab) } set { setBool(newValue, Key.showContactsTab) } }
    public var showCallsTab: Bool { get { bool(Key.showCallsTab) } set { setBool(newValue, Key.showCallsTab) } }
    public var wideChannelPosts: Bool { get { bool(Key.wideChannelPosts) } set { setBool(newValue, Key.wideChannelPosts) } }
    public var channelBottomButton: ChannelBottomButton {
        get { ChannelBottomButton(rawValue: (self.defaults.object(forKey: Key.channelBottomButton) as? Int) ?? 1) ?? .mute }
        set { setInteger(newValue.rawValue, Key.channelBottomButton) }
    }
    public var integratedTabSearch: Bool { get { bool(Key.integratedTabSearch) } set { setBool(newValue, Key.integratedTabSearch) } }
    public var tabSearchOnLeft: Bool { get { bool(Key.tabSearchOnLeft) } set { setBool(newValue, Key.tabSearchOnLeft) } }
    public var tabBarLayout: DGTabBarLayout {
        return DGTabBarLayout(hidden: hideTabBar, contacts: showContactsTab, calls: showCallsTab, wide: wideTabBar, integratedSearch: integratedTabSearch, searchOnLeft: tabSearchOnLeft)
    }
    public var wideTabBar: Bool { get { bool(Key.wideTabBar) } set { setBool(newValue, Key.wideTabBar) } }
    public var showProfileId: Bool { get { bool(Key.showProfileId) } set { setBool(newValue, Key.showProfileId) } }
    public var dialogIdFormat: DialogIdFormat { get { DialogIdFormat(rawValue: integer(Key.dialogIdFormat)) ?? .telegramApi } set { setInteger(newValue.rawValue, Key.dialogIdFormat) } }
    public var relativeOnlineTime: Bool { get { bool(Key.relativeOnlineTime) } set { setBool(newValue, Key.relativeOnlineTime) } }
    public var hidePhoneNumber: Bool { get { bool(Key.hidePhoneNumber) } set { setBool(newValue, Key.hidePhoneNumber) } }
    public var showDc: Bool { get { bool(Key.showDc) } set { setBool(newValue, Key.showDc) } }
    public var showRegistrationDate: Bool { get { bool(Key.showRegistrationDate) } set { setBool(newValue, Key.showRegistrationDate) } }
    public var showChatCreationDate: Bool { get { bool(Key.showChatCreationDate) } set { setBool(newValue, Key.showChatCreationDate) } }
    public var showMutualContact: Bool { get { bool(Key.showMutualContact) } set { setBool(newValue, Key.showMutualContact) } }
    public var confirmCalls: Bool { get { bool(Key.confirmCalls) } set { setBool(newValue, Key.confirmCalls) } }
    public var disableAds: Bool { get { bool(Key.disableAds) } set { setBool(newValue, Key.disableAds) } }
    public var hidePremiumStatuses: Bool { get { bool(Key.hidePremiumStatuses) } set { setBool(newValue, Key.hidePremiumStatuses) } }
    public var disableCustomBackgrounds: Bool { get { bool(Key.disableCustomBackgrounds) } set { setBool(newValue, Key.disableCustomBackgrounds) } }
    public var hideStories: Bool { get { bool(Key.hideStories) } set { setBool(newValue, Key.hideStories) } }
    public var forceSnow: Bool { get { bool(Key.forceSnow) } set { setBool(newValue, Key.forceSnow) } }
    /// No «Соединение…», «Обновление…» or «Ожидание сети…» with a spinner in the chat list title: it keeps its text.
    public var chatListHideStatus: Bool { get { bool(Key.chatListHideStatus) } set { setBool(newValue, Key.chatListHideStatus) } }
    /// No emoji status or Premium star next to the chat list title.
    public var chatListHideEmojiStatus: Bool { get { bool(Key.chatListHideEmojiStatus) } set { setBool(newValue, Key.chatListHideEmojiStatus) } }
    public var chatListCenteredTitle: Bool { get { bool(Key.chatListCenteredTitle) } set { setBool(newValue, Key.chatListCenteredTitle) } }
    public var chatListHideSearch: Bool { get { bool(Key.chatListHideSearch) } set { setBool(newValue, Key.chatListHideSearch) } }
    public var chatListFoldersAtBottom: Bool { get { bool(Key.chatListFoldersAtBottom) } set { setBool(newValue, Key.chatListFoldersAtBottom) } }
    public var chatListTitleMode: ChatListTitleMode {
        get { ChatListTitleMode(rawValue: integer(Key.chatListTitleMode)) ?? .chats }
        set { setInteger(newValue.rawValue, Key.chatListTitleMode) }
    }
    /// An app icon and the island that goes with it: the badge under the notch or the Dynamic Island,
    /// seen on screenshots and screen recordings.
    public struct AppMark {
        /// The caption in both pickers.
        public let title: String
        /// The alternate icon's name (Telegram/Telegram-iOS/<name>.alticon); nil is the default icon.
        public let iconName: String?
        /// The island image in TelegramUI's asset catalog.
        public let islandAssetName: String
    }
    /// Every icon with its island, in picker order, the default icon first. An alternate icon must also be listed
    /// in Telegram/BUILD (alternate_icon_folders) and in both Telegram/Telegram-iOS/AlternateIcons*.plist.
    public static let appMarks: [AppMark] = [
        AppMark(title: "Основной", iconName: nil, islandAssetName: "Components/AppBadge"),
        AppMark(title: "Кольцо", iconName: "DgRing", islandAssetName: "Components/IslandRing"),
        AppMark(title: "Надкушенный", iconName: "DgBitten", islandAssetName: "Components/IslandBitten"),
        AppMark(title: "Пончик-чат", iconName: "DgChat", islandAssetName: "Components/IslandChat"),
        AppMark(title: "Сердечко", iconName: "DgHeart", islandAssetName: "Components/IslandHeart"),
        AppMark(title: "Мордочка", iconName: "DgKawaii", islandAssetName: "Components/IslandKawaii"),
        AppMark(title: "Свинопончик", iconName: "DgPigDonut", islandAssetName: "Components/IslandPigDonut"),
        AppMark(title: "Пиксель", iconName: "DgPixel", islandAssetName: "Components/IslandPixel"),
        AppMark(title: "3D", iconName: "DgDonut3D", islandAssetName: "Components/IslandDonut3D"),
        AppMark(title: "Планета", iconName: "DgPlanet", islandAssetName: "Components/IslandPlanet"),
        AppMark(title: "Самолётик", iconName: "DgPlane", islandAssetName: "Components/IslandPlane"),
        AppMark(title: "Глазурь", iconName: "DgDrip", islandAssetName: "Components/IslandDrip"),
        AppMark(title: "Перспектива", iconName: "DgPerspective", islandAssetName: "Components/IslandPerspective"),
        AppMark(title: "Стикер", iconName: "DgSticker", islandAssetName: "Components/IslandSticker"),
        AppMark(title: "Котопончик", iconName: "DgCatDonut", islandAssetName: "Components/IslandCatDonut"),
        AppMark(title: "Хром", iconName: "DgChrome", islandAssetName: "Components/IslandChrome"),
        AppMark(title: "Стекло", iconName: "DgGlassDonut", islandAssetName: "Components/IslandGlassDonut"),
        AppMark(title: "Призрак", iconName: "DgGhost", islandAssetName: "Components/IslandGhost"),
        AppMark(title: "Кофе", iconName: "DgCoffee", islandAssetName: "Components/IslandCoffee"),
        AppMark(title: "Акварель", iconName: "DgWatercolor", islandAssetName: "Components/IslandWatercolor"),
        AppMark(title: "Бойкиссер", iconName: "DgKisser", islandAssetName: "Components/IslandKisser"),
        AppMark(title: "Бойкиссер 2", iconName: "DgKisserRed", islandAssetName: "Components/IslandKisserRed"),
        AppMark(title: "Котик", iconName: "DgCat", islandAssetName: "Components/IslandCat")
    ]
    /// The mark of an app icon (`UIApplication.alternateIconName`, nil for the default icon); an unknown name gets the default.
    public static func appMarkIndex(iconName: String?) -> Int {
        return DGSimpleSettings.appMarks.firstIndex(where: { $0.iconName == iconName }) ?? 0
    }
    /// The app icon last set from the app, as `UIApplication.alternateIconName` names it (nil for the default icon).
    /// On the phone iOS doesn't report the icon back after a change, so the app keeps it here.
    public var pickedAppIconName: String? {
        get { self.defaults.string(forKey: Key.pickedAppIconName).flatMap { $0.isEmpty ? nil : $0 } }
        set { self.defaults.set(newValue ?? "", forKey: Key.pickedAppIconName) }
    }
    /// False until the icon is first changed from the app in this install.
    public var hasPickedAppIcon: Bool {
        return self.defaults.object(forKey: Key.pickedAppIconName) != nil
    }
    /// Index into `appMarks` of the island picked by hand, shown while `islandFollowsIcon` is off; 0 is the standard badge.
    public var islandStyle: Int {
        get { min(max(integer(Key.islandStyle), 0), DGSimpleSettings.appMarks.count - 1) }
        set { setInteger(min(max(newValue, 0), DGSimpleSettings.appMarks.count - 1), Key.islandStyle) }
    }
    /// «Остров как у иконки»: the island is the current app icon's pair. On by default.
    public var islandFollowsIcon: Bool {
        get { self.defaults.object(forKey: Key.islandFollowsIcon) == nil ? true : bool(Key.islandFollowsIcon) }
        set { setBool(newValue, Key.islandFollowsIcon) }
    }
    /// Index into `appMarks` of the island shown with the given app icon.
    public func islandMarkIndex(iconName: String?) -> Int {
        return self.islandFollowsIcon ? DGSimpleSettings.appMarkIndex(iconName: iconName) : self.islandStyle
    }

    public func localPremium(accountId: Int64) -> Bool {
        return self.defaults.stringArray(forKey: Key.localPremiumPeerIds)?.contains(String(accountId)) ?? false
    }
    public func setLocalPremium(_ enabled: Bool, accountId: Int64) {
        var ids = Set(self.defaults.stringArray(forKey: Key.localPremiumPeerIds) ?? [])
        if enabled { ids.insert(String(accountId)) } else { ids.remove(String(accountId)) }
        self.defaults.set(Array(ids).sorted(), forKey: Key.localPremiumPeerIds)
        NotificationCenter.default.post(name: DGSimpleSettings.didChangeNotification, object: self)
    }

    private let shadowBanLock = NSLock()
    private var shadowBanCache: Set<Int64>?
    private var shadowBanRevealedChats = Set<Int64>()

    // Call with shadowBanLock held.
    private func shadowBanIdsLocked() -> Set<Int64> {
        if let cache = self.shadowBanCache {
            return cache
        }
        let stored = Set((self.defaults.stringArray(forKey: Key.shadowBannedPeerIds) ?? []).compactMap { Int64($0) })
        self.shadowBanCache = stored
        return stored
    }

    /// Peers in the shadow ban, as `PeerId.toInt64()`, for every account: their messages are hidden in groups, channels and comments.
    public var shadowBannedPeerIds: Set<Int64> {
        self.shadowBanLock.lock()
        defer { self.shadowBanLock.unlock() }
        return self.shadowBanIdsLocked()
    }

    public var hasShadowBans: Bool {
        return !self.shadowBannedPeerIds.isEmpty
    }

    public func isShadowBanned(_ peerId: Int64) -> Bool {
        return self.shadowBannedPeerIds.contains(peerId)
    }

    public func setShadowBanned(_ banned: Bool, peerId: Int64) {
        self.shadowBanLock.lock()
        var ids = self.shadowBanIdsLocked()
        let changed: Bool
        if banned {
            changed = ids.insert(peerId).inserted
        } else {
            changed = ids.remove(peerId) != nil
        }
        if changed {
            self.shadowBanCache = ids
            self.defaults.set(ids.map { String($0) }.sorted(), forKey: Key.shadowBannedPeerIds)
        }
        self.shadowBanLock.unlock()
        if changed {
            NotificationCenter.default.post(name: DGSimpleSettings.shadowBanDidChangeNotification, object: self)
        }
    }

    /// Chats where «Показать скрытые» is on, as `PeerId.toInt64()`: in memory only, until the app restarts.
    public var shadowBanRevealedChatIds: Set<Int64> {
        self.shadowBanLock.lock()
        defer { self.shadowBanLock.unlock() }
        return self.shadowBanRevealedChats
    }

    public func isShadowBanRevealed(chatPeerId: Int64) -> Bool {
        return self.shadowBanRevealedChatIds.contains(chatPeerId)
    }

    public func setShadowBanRevealed(_ revealed: Bool, chatPeerId: Int64) {
        self.shadowBanLock.lock()
        let changed: Bool
        if revealed {
            changed = self.shadowBanRevealedChats.insert(chatPeerId).inserted
        } else {
            changed = self.shadowBanRevealedChats.remove(chatPeerId) != nil
        }
        self.shadowBanLock.unlock()
        if changed {
            NotificationCenter.default.post(name: DGSimpleSettings.shadowBanDidChangeNotification, object: self)
        }
    }

    /// A chat that ghost mode read only on this device: the server, and so the senders, still
    /// see it unread. Stored per account (`PeerId.toInt64()` keys) by TelegramCore, together
    /// with the server's read state the local read was made on top of.
    public struct GhostLocalRead: Equatable {
        /// Read here up to this id.
        public var maxIncomingReadId: Int32
        /// The server's read state.
        public var serverMaxIncomingReadId: Int32
        public var serverMarkedUnread: Bool
        /// The server's unread mark is read here as well.
        public var readsServerMark: Bool
        /// Messages the server counts as unread that are read here; nil when that is not known
        /// (the server read part of them on another device).
        public var readCount: Int32?

        public init(maxIncomingReadId: Int32, serverMaxIncomingReadId: Int32, serverMarkedUnread: Bool, readsServerMark: Bool, readCount: Int32?) {
            self.maxIncomingReadId = maxIncomingReadId
            self.serverMaxIncomingReadId = serverMaxIncomingReadId
            self.serverMarkedUnread = serverMarkedUnread
            self.readsServerMark = readsServerMark
            self.readCount = readCount
        }
    }

    private let ghostLocalReadLock = NSLock()
    private var ghostLocalReadCache: [Int64: [Int64: GhostLocalRead]] = [:]

    private func ghostLocalReadsKey(accountPeerId: Int64) -> String {
        return "donutgram.ghost.localReads.\(accountPeerId)"
    }

    // Call with ghostLocalReadLock held.
    private func ghostLocalReadsLocked(accountPeerId: Int64) -> [Int64: GhostLocalRead] {
        if let cached = self.ghostLocalReadCache[accountPeerId] {
            return cached
        }
        var reads: [Int64: GhostLocalRead] = [:]
        for (key, value) in self.defaults.dictionary(forKey: ghostLocalReadsKey(accountPeerId: accountPeerId)) ?? [:] {
            guard let peerId = Int64(key), let values = value as? [Int], values.count == 5 else {
                continue
            }
            let ids = values.prefix(3).compactMap { Int32(exactly: $0) }
            guard ids.count == 3 else {
                continue
            }
            reads[peerId] = GhostLocalRead(maxIncomingReadId: ids[0], serverMaxIncomingReadId: ids[1], serverMarkedUnread: values[3] != 0, readsServerMark: values[4] != 0, readCount: ids[2] >= 0 ? ids[2] : nil)
        }
        self.ghostLocalReadCache[accountPeerId] = reads
        return reads
    }

    public func hasGhostLocalReads(accountPeerId: Int64) -> Bool {
        self.ghostLocalReadLock.lock()
        defer { self.ghostLocalReadLock.unlock() }
        return !self.ghostLocalReadsLocked(accountPeerId: accountPeerId).isEmpty
    }

    public func ghostLocalRead(accountPeerId: Int64, peerId: Int64) -> GhostLocalRead? {
        self.ghostLocalReadLock.lock()
        defer { self.ghostLocalReadLock.unlock() }
        return self.ghostLocalReadsLocked(accountPeerId: accountPeerId)[peerId]
    }

    public func ghostLocalReads(accountPeerId: Int64) -> [Int64: GhostLocalRead] {
        self.ghostLocalReadLock.lock()
        defer { self.ghostLocalReadLock.unlock() }
        return self.ghostLocalReadsLocked(accountPeerId: accountPeerId)
    }

    /// Records the chat's local read, or forgets it (`nil`).
    public func setGhostLocalRead(_ read: GhostLocalRead?, accountPeerId: Int64, peerId: Int64) {
        self.ghostLocalReadLock.lock()
        defer { self.ghostLocalReadLock.unlock() }
        var reads = self.ghostLocalReadsLocked(accountPeerId: accountPeerId)
        guard reads[peerId] != read else {
            return
        }
        reads[peerId] = read
        self.ghostLocalReadCache[accountPeerId] = reads
        var stored: [String: [Int]] = [:]
        for (peerId, read) in reads {
            stored[String(peerId)] = [Int(read.maxIncomingReadId), Int(read.serverMaxIncomingReadId), Int(read.readCount ?? -1), read.serverMarkedUnread ? 1 : 0, read.readsServerMark ? 1 : 0]
        }
        self.defaults.set(stored, forKey: ghostLocalReadsKey(accountPeerId: accountPeerId))
    }

    public var onlyAddedStickers: Bool { get { bool(Key.onlyAddedStickers) } set { setBool(newValue, Key.onlyAddedStickers) } }
    public var infiniteRecentStickers: Bool { get { bool(Key.infiniteRecentStickers) } set { setBool(newValue, Key.infiniteRecentStickers) } }
    public var hidePaidReactions: Bool { get { bool(Key.hidePaidReactions) } set { setBool(newValue, Key.hidePaidReactions) } }
    public var hideBirthdayNotifications: Bool { get { bool(Key.hideBirthdayNotifications) } set { setBool(newValue, Key.hideBirthdayNotifications) } }
    public var hideViaBot: Bool { get { bool(Key.hideViaBot) } set { setBool(newValue, Key.hideViaBot) } }
    public var showPinnedMessagesWithBot: Bool { get { bool(Key.showPinnedMessagesWithBot) } set { setBool(newValue, Key.showPinnedMessagesWithBot) } }
    public var hideBotAutomation: Bool { get { bool(Key.hideBotAutomation) } set { setBool(newValue, Key.hideBotAutomation) } }
    public var removeLinkPreviews: Bool { get { bool(Key.removeLinkPreviews) } set { setBool(newValue, Key.removeLinkPreviews) } }
    // Preserve Telegram's existing sequential playback until the user changes it.
    public var autoplayMedia: Bool {
        get { defaults.object(forKey: Key.autoplayMedia) == nil || bool(Key.autoplayMedia) }
        set { setBool(newValue, Key.autoplayMedia) }
    }
    /// 1: voice messages; 2: round videos. The selection survives disabling the master switch.
    public var autoplayMediaTypes: Int {
        get { defaults.object(forKey: Key.autoplayMediaTypes) == nil ? 3 : integer(Key.autoplayMediaTypes) }
        set { setInteger(newValue & 3, Key.autoplayMediaTypes) }
    }
    public func shouldAutoplayMedia(isRoundVideo: Bool) -> Bool {
        return autoplayMedia && autoplayMediaTypes & (isRoundVideo ? 2 : 1) != 0
    }

    public func shouldShowBotAutomation(hasPinnedMessage: Bool) -> Bool {
        return !hideBotAutomation && !(showPinnedMessagesWithBot && hasPinnedMessage)
    }

    public var hiddenReactions: Int { get { integer(Key.hiddenReactions) } set { setInteger(newValue, Key.hiddenReactions) } }
    public var musicPlaybackExceptions: MusicPlaybackExceptions {
        get { MusicPlaybackExceptions(rawValue: integer(Key.musicPlaybackExceptions) & 7) }
        set { setInteger(newValue.rawValue & 7, Key.musicPlaybackExceptions) }
    }
    public var removeMessageTails: Bool { get { bool(Key.removeMessageTails) } set { setBool(newValue, Key.removeMessageTails) } }
    public var hideShareButton: Bool { get { false } set { } }
    public var disableColoredReplies: Bool { get { bool(Key.disableColoredReplies) } set { setBool(newValue, Key.disableColoredReplies) } }
    public var showForwardDate: Bool { get { bool(Key.showForwardDate) } set { setBool(newValue, Key.showForwardDate) } }
    public var showMessageSeconds: Bool { get { bool(Key.showMessageSeconds) } set { setBool(newValue, Key.showMessageSeconds) } }
    public var downloadTikTok: Bool { get { bool(Key.downloadTikTok) } set { setBool(newValue, Key.downloadTikTok) } }
    public var downloadYouTubeShorts: Bool { get { bool(Key.downloadYouTubeShorts) } set { setBool(newValue, Key.downloadYouTubeShorts) } }
    public var signDownloadedMedia: Bool { get { bool(Key.signDownloadedMedia) } set { setBool(newValue, Key.signDownloadedMedia) } }
    /// Use the device microphone for voice and video recording, even with external inputs connected.
    /// Disabled by default; the switch is «Встроенный микрофон» in «Чаты» ▸ «Запись».
    public var forceBuiltInMicrophone: Bool {
        get { bool(Key.forceBuiltInMicrophone) }
        set { setBool(newValue, Key.forceBuiltInMicrophone) }
    }
    public var startRoundVideoWithRearCamera: Bool { get { bool(Key.startRoundVideoWithRearCamera) } set { setBool(newValue, Key.startRoundVideoWithRearCamera) } }
    public var roundVideoCamera: RoundVideoCamera {
        get {
            if self.defaults.object(forKey: Key.roundVideoCamera) == nil && startRoundVideoWithRearCamera { return .rear }
            return RoundVideoCamera(rawValue: integer(Key.roundVideoCamera)) ?? .front
        }
        set { setInteger(newValue.rawValue, Key.roundVideoCamera) }
    }
    public var rememberRoundVideoCamera: Bool { get { bool(Key.rememberRoundVideoCamera) } set { setBool(newValue, Key.rememberRoundVideoCamera) } }
    public var lastRoundVideoCamera: RoundVideoCamera {
        get {
            if self.defaults.object(forKey: Key.lastRoundVideoCamera) == nil {
                return roundVideoCamera == .rear ? .rear : .front
            }
            return RoundVideoCamera(rawValue: integer(Key.lastRoundVideoCamera)) == .rear ? .rear : .front
        }
        set { setInteger(newValue == .rear ? 1 : 0, Key.lastRoundVideoCamera) }
    }
    public var roundVideoZoomSlider: Bool { get { (self.defaults.object(forKey: Key.roundVideoZoomSlider) as? Bool) ?? true } set { setBool(newValue, Key.roundVideoZoomSlider) } }
    public var staticRoundVideoZoom: Bool { get { bool(Key.staticRoundVideoZoom) } set { setBool(newValue, Key.staticRoundVideoZoom) } }
    public var autoPause: Bool { get { bool(Key.autoPause) } set { setBool(newValue, Key.autoPause) } }
    /// Zero disables seeking; an unset value preserves Telegram's 15-second behavior.
    public var doubleTapSeekSeconds: Int {
        get {
            guard self.defaults.object(forKey: Key.doubleTapSeekSeconds) != nil else { return 15 }
            let value = integer(Key.doubleTapSeekSeconds)
            return [0, 5, 10, 15, 30].contains(value) ? value : 15
        }
        set { setInteger([0, 5, 10, 15, 30].contains(newValue) ? newValue : 15, Key.doubleTapSeekSeconds) }
    }

    public var showPollResultsBeforeVoting: Bool { get { bool(Key.showPollResultsBeforeVoting) } set { setBool(newValue, Key.showPollResultsBeforeVoting) } }
    public var showChannelForwardCount: Bool { get { bool(Key.showChannelForwardCount) } set { setBool(newValue, Key.showChannelForwardCount) } }
    /// Bitmask: video = 1, voice = 2, round video = 4.
    public var autoPauseMedia: Int {
        get { self.defaults.object(forKey: Key.autoPauseMedia) == nil ? 7 : integer(Key.autoPauseMedia) }
        set { setInteger(newValue & 7, Key.autoPauseMedia) }
    }
    public var editedIcon: Bool { get { bool(Key.editedIcon) } set { setBool(newValue, Key.editedIcon) } }
    public var showOnlineIndicator: Bool { get { bool(Key.showOnlineIndicator) } set { setBool(newValue, Key.showOnlineIndicator) } }
    public var hideGreetingSticker: Bool { get { bool(Key.hideGreetingSticker) } set { setBool(newValue, Key.hideGreetingSticker) } }
    public var commaAfterMention: Bool { get { bool(Key.commaAfterMention) } set { setBool(newValue, Key.commaAfterMention) } }
    public var mentionAvatars: Bool { get { bool(Key.mentionAvatars) } set { setBool(newValue, Key.mentionAvatars) } }
    public var gifUnlock: Bool { get { bool(Key.gifUnlock) } set { setBool(newValue, Key.gifUnlock) } }
    public var hideArchive: Bool { get { bool(Key.hideArchive) } set { setBool(newValue, Key.hideArchive) } }
    public var openArchiveOnPull: Bool { get { bool(Key.openArchiveOnPull) } set { setBool(newValue, Key.openArchiveOnPull) } }
    /// 0: standard, 1: fast, 2: ultra. Values outside this range fall back to standard.
    public var downloadAcceleration: Int { get { min(max(integer(Key.downloadAcceleration), 0), 2) } set { setInteger(min(max(newValue, 0), 2), Key.downloadAcceleration) } }
    public var accelerateUpload: Bool { get { bool(Key.accelerateUpload) } set { setBool(newValue, Key.accelerateUpload) } }
    public var transcriptionBackend: TranscriptionBackend {
        get { TranscriptionBackend(rawValue: string(Key.transcriptionBackend)) ?? .auto }
        set { setString(newValue.rawValue, Key.transcriptionBackend) }
    }

    /// Whether to transcribe a message on device. `telegramCanTranscribe` is true when Telegram itself
    /// can transcribe the message right now: Premium, a group boost or a free trial attempt.
    public func usesAppleTranscription(telegramCanTranscribe: Bool) -> Bool {
        switch self.transcriptionBackend {
        case .telegram:
            return false
        case .apple:
            return true
        case .auto:
            return !telegramCanTranscribe
        }
    }
}
