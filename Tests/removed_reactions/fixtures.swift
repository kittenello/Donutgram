import Foundation

protocol MessageAttribute {}
struct PeerId: Hashable {
    var namespace: Int
    var id: Int
}
struct MessageId {
    var peerId: PeerId
    var namespace: Int
    var id: Int
}
struct MessageFlags: OptionSet {
    let rawValue: Int
    static let Incoming = MessageFlags(rawValue: 1)
}
enum Namespaces {
    enum Message { static let Cloud = 0 }
    enum Peer { static let CloudUser = 0 }
}
struct MessageReaction: Equatable {
    enum Reaction: Hashable { case builtin(String), custom(Int64), stars }
    var value: Reaction
    var count: Int32
    var chosenOrder: Int?
    var isRemoved = false
    var isSelected: Bool { chosenOrder != nil }
}
final class ReactionsMessageAttribute: MessageAttribute {
    struct RecentPeer: Equatable {
        var value: MessageReaction.Reaction
        var isLarge: Bool
        var isUnseen: Bool
        var isMy: Bool
        var peerId: PeerId
        var timestamp: Int32?
    }
    var canViewList: Bool
    var isTags: Bool
    var reactions: [MessageReaction]
    var recentPeers: [RecentPeer]
    var topPeers: [Int]
    var removedReactions: [MessageReaction]
    var removedPeers: [RecentPeer]
    init(canViewList: Bool, isTags: Bool, reactions: [MessageReaction], recentPeers: [RecentPeer], topPeers: [Int], removedReactions: [MessageReaction] = [], removedPeers: [RecentPeer] = []) {
        self.canViewList = canViewList
        self.isTags = isTags
        self.reactions = reactions
        self.recentPeers = recentPeers
        self.topPeers = topPeers
        self.removedReactions = removedReactions
        self.removedPeers = removedPeers
    }
}
final class PendingReactionsMessageAttribute: MessageAttribute {}
final class DGSimpleSettings {
    static let shared = DGSimpleSettings()
    var showRemovedReactions = false
    var hidePaidReactions = false
}
func mergedMessageReactions(attributes: [MessageAttribute], isTags: Bool) -> ReactionsMessageAttribute? {
    return attributes.first(where: { $0 is ReactionsMessageAttribute }) as? ReactionsMessageAttribute
}

PRODUCTION_HELPERS

let heart = MessageReaction.Reaction.builtin("heart")
let like = MessageReaction.Reaction.builtin("like")
let alice = PeerId(namespace: 0, id: 1)
let bob = PeerId(namespace: 0, id: 2)
let groupMessage = MessageId(peerId: PeerId(namespace: 2, id: 10), namespace: 0, id: 1)
var checks = 0
func expect(_ value: Bool, _ message: String) {
    checks += 1
    if !value { fatalError(message) }
}
func reaction(_ value: MessageReaction.Reaction = heart, count: Int32 = 1, selected: Bool = false) -> MessageReaction {
    return MessageReaction(value: value, count: count, chosenOrder: selected ? 0 : nil)
}
func peer(_ id: PeerId, value: MessageReaction.Reaction = heart, isMy: Bool = false) -> ReactionsMessageAttribute.RecentPeer {
    return .init(value: value, isLarge: true, isUnseen: true, isMy: isMy, peerId: id, timestamp: 100)
}
func attribute(_ reactions: [MessageReaction] = [], peers: [ReactionsMessageAttribute.RecentPeer] = [], retained: [MessageReaction] = [], retainedPeers: [ReactionsMessageAttribute.RecentPeer] = [], isTags: Bool = false) -> ReactionsMessageAttribute {
    return ReactionsMessageAttribute(canViewList: true, isTags: isTags, reactions: reactions, recentPeers: peers, topPeers: [], removedReactions: retained, removedPeers: retainedPeers)
}
func update(_ previous: ReactionsMessageAttribute, _ current: ReactionsMessageAttribute, id: MessageId = groupMessage, flags: MessageFlags = [], pending: Bool = false) -> ReactionsMessageAttribute {
    var old: [MessageAttribute] = [previous]
    if pending { old.append(PendingReactionsMessageAttribute()) }
    var updated: [MessageAttribute] = [current]
    donutgramMergeRemovedReactions(messageId: id, flags: flags, previous: old, updated: &updated)
    return updated[0] as! ReactionsMessageAttribute
}
func visible(_ attribute: ReactionsMessageAttribute) -> [MessageReaction] {
    return donutgramVisibleMessageReactions(attributes: [attribute], isTags: attribute.isTags)?.reactions ?? []
}

let original = attribute([reaction()], peers: [peer(alice)])
expect(update(original, attribute()).removedReactions.isEmpty, "disabled setting saved a reaction")
DGSimpleSettings.shared.showRemovedReactions = true
let removed = update(original, attribute())
expect(removed.reactions.isEmpty && removed.removedReactions == [reaction()], "server reaction was not separated from local history")
expect(removed.removedPeers.map(\.peerId) == [alice], "removed reactor was lost")
expect(!removed.removedPeers[0].isUnseen && !removed.removedPeers[0].isLarge, "retained reaction stayed unread or animated")
expect(visible(removed).count == 1 && visible(removed)[0].isRemoved && !visible(removed)[0].isSelected, "retained reaction was not marked dimmed")
expect(update(removed, attribute()).removedReactions == removed.removedReactions, "repeated update duplicated a removal")
expect(update(original, attribute(), flags: .Incoming).removedReactions.isEmpty, "incoming message saved reactions")
let localId = MessageId(peerId: groupMessage.peerId, namespace: 1, id: 1)
expect(update(original, attribute(), id: localId).removedReactions.isEmpty, "local message saved reactions")
expect(update(attribute([reaction()], peers: [peer(alice)], isTags: true), attribute()).removedReactions.isEmpty, "saved-message tags were retained as removed reactions")
expect(update(original, attribute(), pending: true).removedReactions.isEmpty, "pending local reaction created a removal")

let own = attribute([reaction(selected: true)], peers: [peer(alice, isMy: true)])
expect(update(own, attribute()).removedReactions.isEmpty, "own reaction was retained")
let ownAndOther = attribute([reaction(count: 2, selected: true)], peers: [peer(alice, isMy: true), peer(bob)])
expect(update(ownAndOther, attribute([reaction()], peers: [peer(bob)])).removedReactions.isEmpty, "own removal was mistaken for another user's")
let otherGone = update(ownAndOther, attribute([reaction(selected: true)], peers: [peer(alice, isMy: true)]))
expect(otherGone.removedReactions == [reaction()] && otherGone.reactions[0].isSelected, "someone else's removal changed the own selection")

let both = attribute([reaction(count: 2)], peers: [peer(alice), peer(bob)])
let oneLeft = update(both, attribute([reaction()], peers: [peer(bob)]))
expect(oneLeft.removedPeers.map(\.peerId) == [alice], "wrong group reactor was recorded")
expect(visible(oneLeft).map(\.isRemoved) == [false, true], "live and retained copies of the same emoji merged")
let differentPerson = update(removed, attribute([reaction()], peers: [peer(bob)]))
expect(differentPerson.removedPeers.map(\.peerId) == [alice], "someone else's reaction cleared the retained one")
let returned = update(differentPerson, both)
expect(returned.removedReactions.isEmpty && returned.removedPeers.isEmpty, "reactor returning kept a duplicate")
let changed = update(original, attribute([reaction(like)], peers: [peer(alice, value: like)]))
expect(changed.removedReactions == [reaction()] && changed.reactions == [reaction(like)], "changing emoji lost the previous reaction")

let complete = attribute([reaction(count: 3)], peers: [peer(alice), peer(bob), peer(PeerId(namespace: 0, id: 3))])
let truncated = attribute([reaction(count: 3)], peers: [peer(bob)])
expect(update(complete, truncated).removedReactions.isEmpty, "truncated recent peers were mistaken for removals")
let unknown = update(attribute([reaction(count: 3)], peers: [peer(alice)]), attribute([reaction(count: 2)], peers: [peer(bob)]))
expect(unknown.removedReactions == [reaction()] && unknown.removedPeers.isEmpty, "anonymous count decrease invented a reactor")
let privateId = MessageId(peerId: bob, namespace: 0, id: 1)
let privateRemoved = update(attribute([reaction()]), attribute(), id: privateId)
expect(privateRemoved.removedPeers.map(\.peerId) == [bob], "private chat failed without recent-peer metadata")
expect(update(privateRemoved, attribute([reaction()]), id: privateId).removedReactions.isEmpty, "private reappearance duplicated a reaction")

let custom = MessageReaction.Reaction.custom(42)
let customRemoved = update(attribute([reaction(custom)], peers: [peer(alice, value: custom)]), attribute())
expect(visible(customRemoved).first?.value == custom && visible(customRemoved).first?.isRemoved == true, "custom emoji was lost")
expect(update(attribute([reaction(.stars, count: 100)], peers: [peer(alice, value: .stars)]), attribute()).removedReactions.isEmpty, "paid reaction was retained")
var omitted: [MessageAttribute] = []
donutgramMergeRemovedReactions(messageId: groupMessage, flags: [], previous: [removed], updated: &omitted)
expect((omitted.first as? ReactionsMessageAttribute)?.removedReactions == removed.removedReactions, "message refresh erased local history")
var firstOmitted: [MessageAttribute] = []
donutgramMergeRemovedReactions(messageId: groupMessage, flags: [], previous: [original], updated: &firstOmitted)
expect(firstOmitted.isEmpty, "omitted server field was treated as a removal")
DGSimpleSettings.shared.showRemovedReactions = false
expect(visible(removed).isEmpty, "disabled setting still displayed retained reactions")
expect(update(removed, attribute([reaction()], peers: [peer(alice)])).removedReactions.isEmpty, "known reappearance while disabled was ignored")
DGSimpleSettings.shared.showRemovedReactions = true
expect(visible(removed).first?.isRemoved == true, "re-enabling erased stored history")
DGSimpleSettings.shared.hidePaidReactions = true
expect(visible(attribute([reaction(.stars), reaction()])).map(\.value) == [heart], "paid reaction hiding changed")
expect(donutgramVisibleMessageReactions(attributes: [], isTags: false) == nil, "empty message acquired a reaction attribute")
print("Removed reactions: \(checks) checks passed")
