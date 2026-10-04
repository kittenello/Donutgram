import XCTest
import Postbox
import TelegramCore
import DGSimpleSettings

final class ShadowBanTests: XCTestCase {
    private let alice = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(101))
    private let bob = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(102))
    private let bot = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(103))
    private let supergroup = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(201))
    private let channel = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(202))
    private let monoforum = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(203))
    private let otherChannel = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(204))
    private let group = PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(301))
    private let secretChat = PeerId(namespace: Namespaces.Peer.SecretChat, id: PeerId.Id._internalFromInt64Value(401))
    private let replies = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(1271266957))

    private func user(_ id: PeerId) -> TelegramUser {
        return TelegramUser(id: id, accessHash: nil, firstName: "User", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func channelPeer(_ id: PeerId, broadcast: Bool, flags: TelegramChannelFlags = []) -> TelegramChannel {
        let info: TelegramChannelInfo = broadcast ? .broadcast(TelegramChannelBroadcastInfo(flags: [])) : .group(TelegramChannelGroupInfo(flags: []))
        return TelegramChannel(id: id, accessHash: nil, title: "Chat", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: info, flags: flags, restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func forward(author: Peer?, source: Peer? = nil) -> MessageForwardInfo {
        return MessageForwardInfo(author: author, source: source, sourceMessageId: nil, date: 0, authorSignature: nil, psaType: nil, flags: [])
    }

    private func message(in chatPeerId: PeerId, chatPeer: Peer? = nil, author: Peer?, incoming: Bool = true, forwardInfo: MessageForwardInfo? = nil, attributes: [MessageAttribute] = [], media: [Media] = []) -> Message {
        var peers = SimpleDictionary<PeerId, Peer>()
        if let chatPeer {
            peers[chatPeer.id] = chatPeer
        }
        if let author {
            peers[author.id] = author
        }
        return Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: chatPeerId, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: incoming ? [.Incoming] : [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: forwardInfo, author: author, text: "", attributes: attributes, media: media, peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func state(banned: [PeerId], revealed: [PeerId] = []) -> DonutgramShadowBan.State {
        return DonutgramShadowBan.State(bannedPeerIds: Set(banned.map { $0.toInt64() }), revealedChatIds: Set(revealed.map { $0.toInt64() }))
    }

    private func index(_ id: Int32) -> MessageIndex {
        return MessageIndex(id: MessageId(peerId: self.supergroup, namespace: Namespaces.Message.Cloud, id: id), timestamp: id)
    }

    func testBannedAuthorIsHiddenInSupergroupAndGroup() {
        let state = self.state(banned: [self.alice])
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.alice)), state: state))
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.group, author: self.user(self.alice)), state: state))
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.bob)), state: state))
    }

    func testPrivateAndSecretChatsAreNeverFiltered() {
        let state = self.state(banned: [self.alice])
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.alice, author: self.user(self.alice)), state: state))
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.secretChat, author: self.user(self.alice)), state: state))
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.bob, author: self.user(self.bob), forwardInfo: self.forward(author: self.user(self.alice))), state: state))
    }

    func testOwnMessagesAreNeverHidden() {
        let state = self.state(banned: [self.alice])
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.alice), incoming: false), state: state))
    }

    func testForwardsFromBannedAuthorOrSourceAreHidden() {
        let state = self.state(banned: [self.alice, self.channel])
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.bob), forwardInfo: self.forward(author: self.user(self.alice))), state: state))
        let source = self.channelPeer(self.channel, broadcast: true)
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.otherChannel, author: self.channelPeer(self.otherChannel, broadcast: true), forwardInfo: self.forward(author: nil, source: source)), state: state))
    }

    func testViaBannedInlineBotIsHidden() {
        let state = self.state(banned: [self.bot])
        let viaBot = InlineBotMessageAttribute(peerId: self.bot, title: nil)
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.bob), attributes: [viaBot]), state: state))
    }

    func testBannedChannelOwnPostsStayVisible() {
        let state = self.state(banned: [self.channel])
        let bannedChannel = self.channelPeer(self.channel, broadcast: true)
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.channel, chatPeer: bannedChannel, author: bannedChannel), state: state))
    }

    func testServiceMessageFromBannedAuthorIsHidden() {
        let state = self.state(banned: [self.alice])
        let action = TelegramMediaAction(action: .pinnedMessageUpdated)
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.alice), media: [action]), state: state))
    }

    func testRepliesChatIsFiltered() {
        let state = self.state(banned: [self.alice])
        XCTAssertTrue(DonutgramShadowBan.isHidden(self.message(in: self.replies, author: self.user(self.replies), forwardInfo: self.forward(author: self.user(self.alice))), state: state))
    }

    func testMonoforumIsNotFiltered() {
        let state = self.state(banned: [self.alice])
        let monoforumPeer = self.channelPeer(self.monoforum, broadcast: false, flags: [.isMonoforum])
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.monoforum, chatPeer: monoforumPeer, author: self.user(self.alice)), state: state))
    }

    func testRevealedChatShowsMessagesButKeepsBannedContent() {
        let state = self.state(banned: [self.alice], revealed: [self.supergroup])
        let message = self.message(in: self.supergroup, author: self.user(self.alice))
        XCTAssertFalse(DonutgramShadowBan.isHidden(message, state: state))
        XCTAssertTrue(DonutgramShadowBan.isBannedContent(message, bannedPeerIds: state.bannedPeerIds))
    }

    func testEmptyListHidesNothing() {
        XCTAssertFalse(DonutgramShadowBan.isHidden(self.message(in: self.supergroup, author: self.user(self.alice)), state: self.state(banned: [])))
    }

    func testPeerIsHiddenOnlyInFilteredChats() {
        let state = self.state(banned: [self.alice])
        XCTAssertTrue(DonutgramShadowBan.isPeerHidden(self.alice, inChat: self.supergroup, state: state))
        XCTAssertFalse(DonutgramShadowBan.isPeerHidden(self.alice, inChat: self.alice, state: state))
        XCTAssertFalse(DonutgramShadowBan.isPeerHidden(self.alice, inChat: self.bob, state: state))
        XCTAssertFalse(DonutgramShadowBan.isPeerHidden(self.alice, inChat: self.supergroup, state: self.state(banned: [self.alice], revealed: [self.supergroup])))
    }

    func testReadIndexMovesOverTrailingHiddenMessages() {
        let window = [self.index(1), self.index(2), self.index(3), self.index(4), self.index(5)]
        XCTAssertEqual(DonutgramShadowBan.readIndexPastHidden(self.index(2), visibleIndices: [self.index(1), self.index(2), self.index(5)], windowIndices: window), self.index(4))
        XCTAssertEqual(DonutgramShadowBan.readIndexPastHidden(self.index(2), visibleIndices: [self.index(1), self.index(2)], windowIndices: window), self.index(5))
        XCTAssertEqual(DonutgramShadowBan.readIndexPastHidden(self.index(5), visibleIndices: [self.index(5)], windowIndices: window), self.index(5))
    }

    func testHiddenWindowWalkKeepsDirectionAndTurnsOnce() {
        var fromBottom = DonutgramShadowBan.HiddenWindowWalk()
        XCTAssertEqual(fromBottom.next(canLoadEarlier: true, canLoadLater: false), .earlier)
        XCTAssertEqual(fromBottom.next(canLoadEarlier: true, canLoadLater: true), .earlier)
        XCTAssertEqual(fromBottom.next(canLoadEarlier: false, canLoadLater: true), .later)
        XCTAssertEqual(fromBottom.next(canLoadEarlier: true, canLoadLater: true), .later)
        XCTAssertNil(fromBottom.next(canLoadEarlier: true, canLoadLater: false))

        var fromMiddle = DonutgramShadowBan.HiddenWindowWalk()
        XCTAssertEqual(fromMiddle.next(canLoadEarlier: true, canLoadLater: true), .later)

        var wholeChatHidden = DonutgramShadowBan.HiddenWindowWalk()
        XCTAssertNil(wholeChatHidden.next(canLoadEarlier: false, canLoadLater: false))
    }

    func testStorageRoundTrip() {
        let settings = DGSimpleSettings.shared
        let peerId = self.alice.toInt64()
        let wasBanned = settings.isShadowBanned(peerId)
        defer {
            settings.setShadowBanned(wasBanned, peerId: peerId)
        }
        settings.setShadowBanned(true, peerId: peerId)
        XCTAssertTrue(settings.isShadowBanned(peerId))
        XCTAssertTrue((UserDefaults.standard.stringArray(forKey: "donutgram.spy.shadowBannedPeerIds") ?? []).contains(String(peerId)))
        settings.setShadowBanned(false, peerId: peerId)
        XCTAssertFalse(settings.isShadowBanned(peerId))
        XCTAssertFalse(settings.isShadowBanRevealed(chatPeerId: self.supergroup.toInt64()))
    }

    // Postbox's window at the bottom holds the newest `count + 1` messages. With the stock count a hidden tail of 45+
    // leaves it empty, and the list re-anchors and reloads forever; the adaptive count must keep the newest visible message.
    private func newestMessagesWindow(messageCount: Int, count: Int) -> ClosedRange<Int> {
        return max(1, messageCount - count) ... messageCount
    }

    func testAdaptiveBottomWindowKeepsNewestVisibleMessage() {
        let messageCount = 5000
        for hiddenTail in [45, 50, 100, 300, 900] {
            let newestVisible = messageCount - hiddenTail
            let count = DonutgramShadowBan.historyWindowCount(44, hiddenCount: hiddenTail)
            XCTAssertTrue(self.newestMessagesWindow(messageCount: messageCount, count: count).contains(newestVisible), "hidden tail \(hiddenTail)")
        }
        XCTAssertFalse(self.newestMessagesWindow(messageCount: messageCount, count: 44).contains(messageCount - 50))
    }

    func testHistoryWindowCountIsStockWithoutHiddenMessagesAndCapped() {
        XCTAssertEqual(DonutgramShadowBan.historyWindowCount(44, hiddenCount: 0), 44)
        XCTAssertEqual(DonutgramShadowBan.historyWindowCount(44, hiddenCount: 10), 64)
        XCTAssertEqual(DonutgramShadowBan.historyWindowCount(44, hiddenCount: 100_000), DonutgramShadowBan.maxHistoryWindowCount)
    }

    func testHiddenWindowWalkGivesUpAfterTooManySteps() {
        var walk = DonutgramShadowBan.HiddenWindowWalk()
        for _ in 0 ..< DonutgramShadowBan.HiddenWindowWalk.maxSteps {
            XCTAssertEqual(walk.next(canLoadEarlier: true, canLoadLater: false), .earlier)
        }
        XCTAssertNil(walk.next(canLoadEarlier: true, canLoadLater: false))
    }

    func testSearchResultsDropHiddenMessagesAndShrinkTotal() {
        let settings = DGSimpleSettings.shared
        let peerId = self.alice.toInt64()
        let wasBanned = settings.isShadowBanned(peerId)
        defer {
            settings.setShadowBanned(wasBanned, peerId: peerId)
        }
        settings.setShadowBanned(true, peerId: peerId)
        let hidden = self.message(in: self.supergroup, author: self.user(self.alice))
        let visible = self.message(in: self.supergroup, author: self.user(self.bob))
        let result = DonutgramShadowBan.filteringHidden(SearchMessagesResult(messages: [hidden, visible], readStates: [:], threadInfo: [:], totalCount: 10, completed: false))
        XCTAssertEqual(result.messages.count, 1)
        XCTAssertEqual(result.messages.first?.author?.id, self.bob)
        XCTAssertEqual(result.totalCount, 9)
    }
}
