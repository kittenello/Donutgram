import XCTest
import Postbox
@testable import TelegramCore

final class RemovedReactionCodingTests: XCTestCase {
    func testRemovedReactionsRoundTripSeparatelyFromServerResults() {
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(42))
        let removed = MessageReaction(value: .custom(123), count: 1, chosenOrder: nil)
        let peer = ReactionsMessageAttribute.RecentPeer(value: removed.value, isLarge: false, isUnseen: false, isMy: false, peerId: peerId, timestamp: 100)
        let original = ReactionsMessageAttribute(canViewList: true, isTags: false, reactions: [], recentPeers: [], topPeers: [], removedReactions: [removed], removedPeers: [peer])
        let encoder = PostboxEncoder()
        original.encode(encoder)
        let decoded = ReactionsMessageAttribute(decoder: PostboxDecoder(buffer: MemoryBuffer(data: encoder.makeData())))
        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.reactions.isEmpty)
        XCTAssertFalse(decoded.hasUnseen)
        XCTAssertEqual(decoded.associatedPeerIds, [peerId])
        XCTAssertEqual(decoded.associatedMediaIds, [MediaId(namespace: Namespaces.Media.CloudFile, id: 123)])
        XCTAssertEqual(decoded.withAllSeen().removedReactions, [removed])
        XCTAssertEqual(decoded.withAllSeen().removedPeers, [peer])
    }

    func testOldAttributeDecodesWithoutRemovalHistory() {
        let encoder = PostboxEncoder()
        encoder.encodeBool(true, forKey: "vl")
        encoder.encodeBool(false, forKey: "tg")
        encoder.encodeObjectArray([MessageReaction(value: .builtin("heart"), count: 1, chosenOrder: nil)], forKey: "r")
        encoder.encodeObjectArray([ReactionsMessageAttribute.RecentPeer](), forKey: "rp")
        encoder.encodeObjectArray([ReactionsMessageAttribute.TopPeer](), forKey: "tp")
        let decoded = ReactionsMessageAttribute(decoder: PostboxDecoder(buffer: MemoryBuffer(data: encoder.makeData())))
        XCTAssertEqual(decoded.reactions.count, 1)
        XCTAssertTrue(decoded.removedReactions.isEmpty)
        XCTAssertTrue(decoded.removedPeers.isEmpty)
    }
}
