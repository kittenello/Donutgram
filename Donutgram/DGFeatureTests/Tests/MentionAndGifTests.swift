import XCTest
import UIKit
import CoreText
import Postbox
import TelegramCore
import TextFormat
import InteractiveTextComponent
import DGSimpleSettings

final class MentionAndGifTests: XCTestCase {
    private let embeddedKey = NSAttributedString.Key("Attribute__EmbeddedItem")
    private let font = UIFont.systemFont(ofSize: 17.0)

    private func text(_ string: String) -> NSAttributedString {
        return NSAttributedString(string: string, attributes: [.font: self.font, .foregroundColor: UIColor.blue])
    }

    /// The message text as the chat bubble renders it before adding the avatars.
    private func rendered(_ text: String, _ entities: [MessageTextEntity]) -> NSAttributedString {
        return stringWithAppliedEntities(text, entities: entities, baseColor: .black, linkColor: .blue, codeBlockTitleColor: .blue, codeBlockAccentColor: .blue, codeBlockBackgroundColor: .lightGray, baseFont: self.font, linkFont: self.font, boldFont: self.font, italicFont: self.font, boldItalicFont: self.font, fixedFont: self.font, blockQuoteFont: self.font, message: nil)
    }

    private func avatarLocations(_ text: NSAttributedString) -> [Int] {
        var locations: [Int] = []
        text.enumerateAttribute(self.embeddedKey, in: NSRange(location: 0, length: text.length), options: []) { value, range, _ in
            if value != nil {
                locations.append(range.location)
            }
        }
        return locations
    }

    private func group(rights: TelegramChatBannedRightsFlags = [], role: TelegramGroupRole = .member) -> TelegramGroup {
        return TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(1)), title: "Test", photo: [], participantCount: 2, role: role, membership: .Member, flags: [], defaultBannedRights: TelegramChatBannedRights(flags: rights, untilDate: Int32.max), migrationReference: nil, creationDate: 0, version: 1)
    }

    func testMentionPreservesTextAndUTF16OffsetsAfterEmoji() {
        let raw = "🙂 @alice, ссылка"
        let range = (raw as NSString).range(of: "@alice")
        let source = self.rendered(raw, [MessageTextEntity(range: range.location ..< NSMaxRange(range), type: .Mention)])
        let result = textWithMentionAvatars(source, peers: [])
        XCTAssertEqual(result.string, source.string)
        XCTAssertEqual(result.length, source.length)
        XCTAssertEqual(self.avatarLocations(result), [range.location])
        XCTAssertNil(result.attribute(self.embeddedKey, at: range.location + 1, effectiveRange: nil))
        XCTAssertNotNil(result.attribute(NSAttributedString.Key(kCTRunDelegateAttributeName as String), at: range.location, effectiveRange: nil))
    }

    func testNamedMentionPreservesComposedFirstCharacter() {
        let peer = self.group()
        let raw = "👩‍💻 Анна"
        let source = self.rendered(raw, [MessageTextEntity(range: 0 ..< (raw as NSString).length, type: .TextMention(peerId: peer.id))])
        let result = textWithMentionAvatars(source, peers: [EnginePeer(peer)])
        XCTAssertEqual(result.string, source.string)
        let first = (raw as NSString).rangeOfComposedCharacterSequence(at: 0)
        for index in 0 ..< NSMaxRange(first) {
            XCTAssertNotNil(result.attribute(self.embeddedKey, at: index, effectiveRange: nil))
        }
        XCTAssertNil(result.attribute(self.embeddedKey, at: NSMaxRange(first), effectiveRange: nil))
    }

    func testMentionAfterRenderedDateGetsItsOwnAvatar() {
        // A formatted date is shown as the date, so the text before a mention can be longer or
        // shorter than in the message's raw text, which the entities' offsets index. Only the
        // rendered text says where the mention is now.
        let raw = "2026-01-01 12:00 @alice"
        let source = NSMutableAttributedString(attributedString: self.rendered(raw, [
            MessageTextEntity(range: 0 ..< 16, type: .FormattedDate(format: .relative, date: 1767268800)),
            MessageTextEntity(range: 17 ..< 23, type: .Mention)
        ]))
        source.replaceCharacters(in: NSRange(location: 0, length: 16), with: "1 января 2026 г. в 12:00")
        let mention = (source.string as NSString).range(of: "@alice")
        XCTAssertNotEqual(mention.location, 17)
        let result = textWithMentionAvatars(source, peers: [])
        XCTAssertEqual(self.avatarLocations(result), [mention.location])
    }

    func testSpoilersAndCodeDoNotResolveMentionAvatars() {
        let source = self.rendered("@alice @bob @carol", [
            MessageTextEntity(range: 0 ..< 6, type: .Mention),
            MessageTextEntity(range: 0 ..< 6, type: .Spoiler),
            MessageTextEntity(range: 7 ..< 11, type: .Mention),
            MessageTextEntity(range: 7 ..< 11, type: .Code),
            MessageTextEntity(range: 12 ..< 18, type: .Mention),
            MessageTextEntity(range: 12 ..< 18, type: .Pre(language: nil))
        ])
        let result = textWithMentionAvatars(source, peers: [])
        XCTAssertEqual(self.avatarLocations(result), [])
    }

    func testTextWithoutMentionsIsUntouched() {
        let source = self.text("@alice")
        let result = textWithMentionAvatars(source, peers: [])
        XCTAssertEqual(result, source)
    }

    func testMentionLinkAndFollowingTextStayAtOriginalOffsets() {
        let source = self.rendered("@alice и @bob", [MessageTextEntity(range: 0 ..< 6, type: .Mention), MessageTextEntity(range: 9 ..< 13, type: .Mention)])
        let result = textWithMentionAvatars(source, peers: [])
        XCTAssertEqual(result.string, source.string)
        for index in 0 ..< 6 {
            XCTAssertEqual(result.attribute(NSAttributedString.Key(TelegramTextAttributes.PeerTextMention), at: index, effectiveRange: nil) as? String, "@alice")
        }
        XCTAssertEqual(self.avatarLocations(result), [0, 9])
    }

    func testOrdinarySilentVideosAreNotTreatedAsConvertedGifs() {
        let resource = LocalFileMediaResource(fileId: 1)
        let video = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: 1), partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: 10, attributes: [.FileName(fileName: "video.mp4"), .Video(duration: 1.0, size: PixelDimensions(width: 100, height: 100), flags: [.isSilent], preloadSize: nil, coverTime: nil, videoCodec: nil)], alternativeRepresentations: [])
        XCTAssertFalse(donutgramIsGifVideo(video))
        let converted = video.withUpdatedAttributes([.FileName(fileName: "gif-video.mp4"), .Video(duration: 1.0, size: PixelDimensions(width: 100, height: 100), flags: [.isSilent], preloadSize: nil, coverTime: nil, videoCodec: nil)])
        XCTAssertTrue(donutgramIsGifVideo(converted))
        XCTAssertFalse(converted.isAnimated)
        XCTAssertTrue(converted.isVideo)
    }

    func testGifFallbackRequiresVideoPermissionAndEnabledSetting() {
        let previous = DGSimpleSettings.shared.gifUnlock
        defer { DGSimpleSettings.shared.gifUnlock = previous }
        DGSimpleSettings.shared.gifUnlock = true
        XCTAssertTrue(donutgramCanSendGifAsVideo(peer: self.group(rights: [.banSendGifs, .banSendStickers])))
        XCTAssertFalse(donutgramCanSendGifAsVideo(peer: self.group(rights: [.banSendGifs, .banSendVideos])))
        XCTAssertFalse(donutgramCanSendGifAsVideo(peer: self.group(rights: [.banSendGifs, .banSendMedia])))
        XCTAssertFalse(donutgramCanSendGifAsVideo(peer: self.group()))
        XCTAssertFalse(donutgramCanSendGifAsVideo(peer: self.group(rights: [.banSendGifs], role: .creator(rank: nil))))
        DGSimpleSettings.shared.gifUnlock = false
        XCTAssertFalse(donutgramCanSendGifAsVideo(peer: self.group(rights: [.banSendGifs])))
    }
}
