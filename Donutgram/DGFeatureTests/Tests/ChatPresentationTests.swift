import XCTest
import Foundation
import Postbox
import TelegramCore
import DGSimpleSettings

final class ChatPresentationTests: XCTestCase {
    private var hidePaidReactions = false
    private var removeLinkPreviews = false

    override func setUp() {
        super.setUp()
        self.hidePaidReactions = DGSimpleSettings.shared.hidePaidReactions
        self.removeLinkPreviews = DGSimpleSettings.shared.removeLinkPreviews
    }

    override func tearDown() {
        DGSimpleSettings.shared.hidePaidReactions = self.hidePaidReactions
        DGSimpleSettings.shared.removeLinkPreviews = self.removeLinkPreviews
        super.tearDown()
    }

    func testPaidReactionsAreFilteredOnlyForPresentation() {
        let ordinary = MessageReaction(value: .builtin("test"), count: 7, chosenOrder: nil)
        let paid = MessageReaction(value: .stars, count: 42, chosenOrder: nil)
        let source = ReactionsMessageAttribute(canViewList: true, isTags: false, reactions: [ordinary, paid], recentPeers: [], topPeers: [])
        DGSimpleSettings.shared.hidePaidReactions = true
        let visible = donutgramVisibleMessageReactions(attributes: [source], isTags: false)
        XCTAssertEqual(visible?.reactions, [ordinary])
        XCTAssertEqual(visible?.canViewList, true)
        XCTAssertEqual(mergedMessageReactions(attributes: [source], isTags: false)?.reactions, [ordinary, paid])
        DGSimpleSettings.shared.hidePaidReactions = false
        XCTAssertEqual(donutgramVisibleMessageReactions(attributes: [source], isTags: false)?.reactions, [ordinary, paid])
    }

    func testRemovingLinkPreviewPreservesOtherOutgoingAttributesAndFlags() {
        DGSimpleSettings.shared.removeLinkPreviews = true
        let schedule = OutgoingScheduleInfoMessageAttribute(scheduleTime: 2000000000, repeatPeriod: nil)
        let originalFlags = OutgoingContentInfoFlags(rawValue: 1 << 5)
        let attributes: [MessageAttribute] = [schedule, OutgoingContentInfoMessageAttribute(flags: originalFlags), WebpagePreviewMessageAttribute(leadingPreview: true, forceLargeMedia: true, isManuallyAdded: true, isSafe: false)]
        let result = donutgramOutgoingMessageAttributes(attributes)
        XCTAssertFalse(result.contains(where: { $0 is WebpagePreviewMessageAttribute }))
        XCTAssertEqual((result.first as? OutgoingScheduleInfoMessageAttribute)?.scheduleTime, schedule.scheduleTime)
        let flags = result.compactMap { $0 as? OutgoingContentInfoMessageAttribute }.first?.flags
        XCTAssertEqual(flags?.rawValue, originalFlags.union(.disableLinkPreviews).rawValue)
        XCTAssertEqual(donutgramOutgoingMessageAttributes(result).count, result.count)
    }

    func testDisabledSettingPreservesManualPreviewChoice() {
        DGSimpleSettings.shared.removeLinkPreviews = false
        let preview = WebpagePreviewMessageAttribute(leadingPreview: false, forceLargeMedia: nil, isManuallyAdded: true, isSafe: false)
        XCTAssertTrue(donutgramOutgoingMessageAttributes([preview]).first is WebpagePreviewMessageAttribute)
        let manual = OutgoingContentInfoMessageAttribute(flags: [.disableLinkPreviews])
        XCTAssertEqual((donutgramOutgoingMessageAttributes([manual]).first as? OutgoingContentInfoMessageAttribute)?.flags, .disableLinkPreviews)
        DGSimpleSettings.shared.removeLinkPreviews = true
        XCTAssertEqual((donutgramOutgoingMessageAttributes([]).first as? OutgoingContentInfoMessageAttribute)?.flags, .disableLinkPreviews)
    }
}
