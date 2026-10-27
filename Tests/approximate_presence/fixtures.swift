import Foundation

public protocol PostboxCoding {
    init(decoder: PostboxDecoder)
    func encode(_ encoder: PostboxEncoder)
}
public protocol PeerPresence: PostboxCoding {}
public final class PostboxEncoder {
    var values: [String: Int32] = [:]
    public func encodeInt32(_ value: Int32, forKey key: String) { values[key] = value }
    public func encodeBool(_ value: Bool, forKey key: String) { values[key] = value ? 1 : 0 }
}
public final class PostboxDecoder {
    let values: [String: Int32]
    init(_ values: [String: Int32]) { self.values = values }
    public func decodeInt32ForKey(_ key: String, orElse value: Int32) -> Int32 { values[key] ?? value }
    public func decodeBoolForKey(_ key: String, orElse value: Bool) -> Bool { values[key].map { $0 != 0 } ?? value }
}
struct PeerId: Hashable { let namespace: Int; let id: Int }
enum Namespaces {
    enum Peer { static let CloudUser = 0; static let CloudGroup = 1; static let CloudChannel = 2; static let SecretChat = 3 }
    enum Message { static let Cloud = 0; static let ScheduledCloud = 1 }
}
protocol Peer {}
struct UserFlags: OptionSet {
    let rawValue: Int
    static let isSupport = UserFlags(rawValue: 1)
}
struct TelegramUser: Peer {
    var botInfo: Int? = nil
    var isDeleted = false
    var flags: UserFlags = []
}
struct TelegramGroup: Peer {
    enum Membership { case Member, Left, Removed }
    var membership: Membership = .Member
}
struct TelegramChannel: Peer {
    enum Info { case group, broadcast }
    enum Participation { case member, left, kicked }
    var info: Info = .group
    var participationStatus: Participation = .member
}
protocol Media {}
struct TelegramMediaAction: Media {}
protocol MessageAttribute {}
struct NotificationInfoMessageAttribute: MessageAttribute {
    struct Flags: OptionSet {
        let rawValue: Int
        static let automaticMessage = Flags(rawValue: 1)
    }
    var flags: Flags
}
struct InlineBusinessBotMessageAttribute: MessageAttribute {}
struct StoreMessageFlags: OptionSet {
    let rawValue: Int
    static let Incoming = StoreMessageFlags(rawValue: 1)
    static let WasScheduled = StoreMessageFlags(rawValue: 2)
}
struct MessageId { var peerId: PeerId; var namespace: Int = 0 }
enum StoreMessageId {
    case Id(MessageId)
    case Partial(PeerId)
    var peerId: PeerId {
        switch self { case let .Id(id): return id.peerId; case let .Partial(id): return id }
    }
}
struct StoreMessage {
    var id: StoreMessageId
    var authorId: PeerId?
    var timestamp: Int32
    var flags: StoreMessageFlags = [.Incoming]
    var media: [Media] = []
    var attributes: [MessageAttribute] = []
}
final class Transaction {
    var peers: [PeerId: Peer] = [:]
    var presences: [PeerId: PeerPresence] = [:]
    func getPeer(_ id: PeerId) -> Peer? { peers[id] }
    func getPeerPresence(peerId: PeerId) -> PeerPresence? { presences[peerId] }
    func updatePeerPresencesInternal(presences: [PeerId: PeerPresence], merge: (PeerPresence, PeerPresence) -> PeerPresence) {
        for (id, presence) in presences {
            self.presences[id] = self.presences[id].map { merge($0, presence) } ?? presence
        }
    }
}
final class DGSimpleSettings {
    static let shared = DGSimpleSettings(defaults: UserDefaults(suiteName: "approximate-presence-\(UUID().uuidString)")!)
    static let didChangeNotification = Notification.Name("settings-changed")
    let defaults: UserDefaults
    private enum Key {
        static let approximateLastSeen = "donutgram.spy.approximateLastSeen"
        static let approximateLastSeenStartedAt = "donutgram.spy.approximateLastSeenStartedAt"
    }
    init(defaults: UserDefaults) {
        self.defaults = defaults
        SETTINGS_MIGRATION
    }
    SETTINGS_MEMBERS
}
public enum EnginePeer {
    public struct Presence {
        var status: UserPresenceStatus
        var donutgramLastMessageTimestamp: Int32
    }
}
public struct PresentationDateTimeFormat {
    enum DateFormat { case monthFirst, dayFirst }
    var dateSeparator = "."
    var dateSuffix = ""
    var requiresFullYear = true
    var dateFormat: DateFormat = .dayFirst
}
public struct PresentationStrings {
    var baseLanguageCode: String
    struct Formatted { var string: String }
    func LastSeen_AtDate(_ value: String) -> Formatted { Formatted(string: "last seen \(value)") }
}

PRODUCTION_CODE

func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), name)
}

let account = PeerId(namespace: 0, id: 1)
let user = PeerId(namespace: 0, id: 2)
let bot = PeerId(namespace: 0, id: 3)
let other = PeerId(namespace: 0, id: 4)
let group = PeerId(namespace: 1, id: 10)
let leftGroup = PeerId(namespace: 1, id: 11)
let supergroup = PeerId(namespace: 2, id: 12)
let channel = PeerId(namespace: 2, id: 13)
let secret = PeerId(namespace: 3, id: 14)
let transaction = Transaction()
transaction.peers = [account: TelegramUser(), user: TelegramUser(), bot: TelegramUser(botInfo: 1), other: TelegramUser(), group: TelegramGroup(), leftGroup: TelegramGroup(membership: .Left), supergroup: TelegramChannel(), channel: TelegramChannel(info: .broadcast)]
let now = Int32(Date().timeIntervalSince1970)
func message(_ chat: PeerId, author: PeerId? = user, time: Int32 = now - 60, flags: StoreMessageFlags = [.Incoming], media: [Media] = [], attributes: [MessageAttribute] = [], namespace: Int = 0) -> StoreMessage {
    StoreMessage(id: .Id(MessageId(peerId: chat, namespace: namespace)), authorId: author, timestamp: time, flags: flags, media: media, attributes: attributes)
}
func recorded() -> Int32 { (transaction.presences[user] as? TelegramUserPresence)?.donutgramLastMessageTimestamp ?? 0 }
func record(_ messages: [StoreMessage]) { donutgramRecordMessageActivity(transaction: transaction, accountPeerId: account, messages: messages) }

DGSimpleSettings.shared.approximateLastSeen = true
let firstActivation = DGSimpleSettings.shared.approximateLastSeenStartedAt!
transaction.presences[user] = TelegramUserPresence(status: .recently(isHidden: true), lastActivity: now - 50)
record([message(user, time: firstActivation - 1), message(group, time: firstActivation)])
check(recorded() == 0, "ignore messages from before activation including the boundary second")
let oldEvidence = EnginePeer.Presence(status: .recently(isHidden: true), donutgramLastMessageTimestamp: firstActivation - 1)
check(donutgramApproximateLastSeenTimestamp(oldEvidence, relativeTo: now) == nil, "hide cached evidence from before activation")
DGSimpleSettings.shared.defaults.set(now - 120, forKey: "donutgram.spy.approximateLastSeenStartedAt")
DGSimpleSettings.shared.approximateLastSeen = true
check(DGSimpleSettings.shared.approximateLastSeenStartedAt == now - 120, "setting an enabled toggle again keeps the activation")
record([message(user)])
check(recorded() == now - 60, "private message")
record([message(group, time: now - 40), message(supergroup, time: now - 20)])
check(recorded() == now - 20, "newest mutual group message")
record([message(user, time: now - 90)])
check(recorded() == now - 20, "older history cannot move time backwards")
record([message(leftGroup, time: now - 1), message(channel, time: now - 1), message(secret, time: now - 1), message(other, time: now - 1)])
check(recorded() == now - 20, "exclude left groups, broadcasts, secret chats and unrelated private chats")
record([message(user, time: now - 1, flags: [.WasScheduled]), message(user, time: now - 1, media: [TelegramMediaAction()]), message(user, time: now - 1, attributes: [NotificationInfoMessageAttribute(flags: [.automaticMessage])]), message(user, time: now - 1, attributes: [InlineBusinessBotMessageAttribute()]), message(user, time: now - 1, namespace: 1)])
check(recorded() == now - 20, "exclude scheduled, service, automatic and business bot messages")
transaction.presences[bot] = TelegramUserPresence(status: .recently(isHidden: false), lastActivity: 0)
transaction.presences[account] = TelegramUserPresence(status: .recently(isHidden: false), lastActivity: 0)
record([message(group, author: nil), message(group, author: channel), message(group, author: bot), message(group, author: account)])
check((transaction.presences[bot] as! TelegramUserPresence).donutgramLastMessageTimestamp == 0 && (transaction.presences[account] as! TelegramUserPresence).donutgramLastMessageTimestamp == 0 && transaction.presences[channel] == nil, "exclude bots, anonymous senders and self")
record([message(other, author: other)])
check(transaction.presences[other] == nil, "no presence is made up for a user the server gave none")
DGSimpleSettings.shared.approximateLastSeen = false
record([message(user, time: now - 1)])
check(recorded() == now - 20, "disabled collection")
check(DGSimpleSettings.shared.approximateLastSeenStartedAt == nil, "disabled tracking has no activation")
DGSimpleSettings.shared.approximateLastSeen = true
let nextActivation = DGSimpleSettings.shared.approximateLastSeenStartedAt!
check(nextActivation >= firstActivation && nextActivation > now - 120, "reenabling starts a new tracking period")
check(donutgramApproximateLastSeenTimestamp(EnginePeer.Presence(status: .recently(isHidden: true), donutgramLastMessageTimestamp: recorded()), relativeTo: now) == nil, "reenabling hides previous tracking data")
record([message(user, time: now - 10)])
check(recorded() == now - 20, "delayed messages from a previous period are ignored")
let reopenedSettings = DGSimpleSettings(defaults: DGSimpleSettings.shared.defaults)
check(reopenedSettings.approximateLastSeenStartedAt == nextActivation, "restart preserves activation")
DGSimpleSettings.shared.defaults.set(now - 120, forKey: "donutgram.spy.approximateLastSeenStartedAt")
record([message(user, time: now - 10)])
check(recorded() == now - 10, "new messages during the tracking period update evidence")
record([message(user, time: now + 60)])
check(recorded() == now + 60, "a message dated ahead of this device's clock counts")
let legacyDefaults = UserDefaults(suiteName: "approximate-presence-migration-\(UUID().uuidString)")!
legacyDefaults.set(true, forKey: "donutgram.spy.approximateLastSeen")
let migratedSettings = DGSimpleSettings(defaults: legacyDefaults)
check(migratedSettings.approximateLastSeenStartedAt != nil && migratedSettings.approximateLastSeenStartedAt! >= firstActivation, "an already enabled old version starts tracking at migration")
let stored = transaction.presences[user] as! TelegramUserPresence
check(stored.status == .recently(isHidden: true) && stored.lastActivity == now - 50, "message evidence leaves real presence unchanged")
let encoder = PostboxEncoder()
stored.encode(encoder)
check(TelegramUserPresence(decoder: PostboxDecoder(encoder.values)) == stored, "persist through restart")
check(TelegramUserPresence(decoder: PostboxDecoder(["v": 2, "la": 5])).donutgramLastMessageTimestamp == 0, "read old database format")
check(stored != TelegramUserPresence(status: stored.status, lastActivity: stored.lastActivity), "evidence changes presence equality")
let recent = EnginePeer.Presence(status: .recently(isHidden: true), donutgramLastMessageTimestamp: now - 60)
check(donutgramApproximateLastSeenTimestamp(recent, relativeTo: now) == now - 60, "recent evidence")
check(donutgramApproximateLastSeenTimestamp(recent, relativeTo: now + 3 * 86400) == nil, "expire old evidence")
check(donutgramApproximateLastSeenTimestamp(recent, relativeTo: now - 120) == nil, "reject future evidence")
check(donutgramApproximateLastSeenTimestamp(EnginePeer.Presence(status: .present(until: now + 60), donutgramLastMessageTimestamp: now - 60), relativeTo: now) == nil, "keep exact online status")
check(donutgramApproximateLastSeenTimestamp(EnginePeer.Presence(status: .lastWeek(isHidden: false), donutgramLastMessageTimestamp: now - 60), relativeTo: now) == nil, "keep last week status")
check(donutgramApproximateLastSeenTimestamp(EnginePeer.Presence(status: .recently(isHidden: false), donutgramLastMessageTimestamp: 0), relativeTo: now) == nil, "no invented estimate")
NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
let iso = ISO8601DateFormatter()
let sample = Int32(iso.date(from: "2026-10-24T00:12:41Z")!.timeIntervalSince1970)
let format = PresentationDateTimeFormat()
check(stringForDonutgramApproximatePresence(strings: PresentationStrings(baseLanguageCode: "ru"), dateTimeFormat: format, timestamp: sample, relativeTo: sample + 3600) == "был(а) в ~00:12:41", "screenshot format including seconds")
check(stringForDonutgramApproximatePresence(strings: PresentationStrings(baseLanguageCode: "ru-custom"), dateTimeFormat: format, timestamp: sample, relativeTo: sample + 86400) == "был(а) 24.10.2026 в ~00:12:41", "date for older messages and custom language")
check(stringForDonutgramApproximatePresence(strings: PresentationStrings(baseLanguageCode: "en"), dateTimeFormat: format, timestamp: sample, relativeTo: sample + 3600) == "last seen ~00:12:41", "English fallback")
print("approximate presence regression checks passed")
