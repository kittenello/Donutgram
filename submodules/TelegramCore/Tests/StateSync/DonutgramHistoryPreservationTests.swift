import Foundation
import DGSimpleSettings
import XCTest
import Postbox
@testable import TelegramCore

final class DonutgramHistoryPreservationTests: StateSyncTestCase {
    private func storeSavedMessage(peerId: PeerId, id: Int32) -> MessageId {
        let messageId = self.messageId(peerId, id)
        let message = StoreMessage(id: messageId, customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: self.baseDate, flags: [.Incoming], tags: [], globalTags: [], localTags: [.donutgramDeleted, .donutgramHasEditHistory], forwardInfo: nil, authorId: peerId, text: "saved", attributes: [], media: [])
        self.fixture.transaction { transaction -> Void in
            let _ = transaction.addMessages([message], location: .Random)
        }
        return messageId
    }

    func testReceivedDeletionKeepsAnAlreadySavedSnapshot() {
        let peerId = self.seedUserChat(200)
        let messageId = self.storeSavedMessage(peerId: peerId, id: 30)
        let mediaBox = self.fixture.postbox.mediaBox

        let deleted = self.fixture.transaction { transaction -> [MessageId] in
            return deleteStoredMessagesAsReceivedDeletion(transaction: transaction, mediaBox: mediaBox, ids: [messageId])
        }

        XCTAssertEqual(deleted, [])
        XCTAssertEqual(self.fixture.message(messageId)?.text, "saved")
        XCTAssertEqual(self.fixture.message(messageId)?.localTags.contains(.donutgramDeleted), true)
    }

    func testMissingConfirmationSavesMessagesWhenPreservationIsEnabled() {
        let settings = DGSimpleSettings.shared
        let previousSaveDeletedMessages = settings.saveDeletedMessages
        settings.saveDeletedMessages = true
        defer { settings.saveDeletedMessages = previousSaveDeletedMessages }
        let peerId = self.seedUserChat(206)
        let messageId = self.messageId(peerId, 40)
        self.fixture.storeMessage(peerId: peerId, id: 40, timestamp: self.baseDate, authorId: peerId, text: "preserve me")
        let mediaBox = self.fixture.postbox.mediaBox

        let deleted = self.fixture.transaction { transaction -> [MessageId] in
            guard let current = transaction.getMessage(messageId) else {
                XCTFail("the message is missing")
                return []
            }
            let confirmation = StoredMessageConfirmation(existing: [], peers: AccumulatedPeers(), missing: [messageId])
            return applyStoredMessageConfirmation(transaction: transaction, accountPeerId: StateSyncFixture.accountPeerId, mediaBox: mediaBox, confirmation: confirmation, versions: [messageId: current.stableVersion])
        }

        XCTAssertEqual(deleted, [])
        XCTAssertEqual(self.fixture.message(messageId)?.text, "preserve me")
        XCTAssertEqual(self.fixture.message(messageId)?.localTags.contains(.donutgramDeleted), true)
    }

    func testConfirmationRefreshStoresThePreviousTextAsARevision() {
        let settings = DGSimpleSettings.shared
        let previousSaveEditHistory = settings.saveEditHistory
        settings.saveEditHistory = true
        defer { settings.saveEditHistory = previousSaveEditHistory }
        let peerId = self.seedUserChat(200)
        let messageId = self.storeSavedMessage(peerId: peerId, id: 31)
        let fresh = StoreMessage(id: messageId, customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: self.baseDate, flags: [.Incoming], tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: peerId, text: "edited", attributes: [EditedMessageAttribute(date: self.baseDate + 10, isHidden: false)], media: [])
        let mediaBox = self.fixture.postbox.mediaBox

        let deleted = self.fixture.transaction { transaction -> [MessageId] in
            guard let current = transaction.getMessage(messageId) else {
                XCTFail("the saved message is missing")
                return []
            }
            let confirmation = StoredMessageConfirmation(existing: [fresh], peers: AccumulatedPeers(), missing: [])
            return applyStoredMessageConfirmation(transaction: transaction, accountPeerId: StateSyncFixture.accountPeerId, mediaBox: mediaBox, confirmation: confirmation, versions: [messageId: current.stableVersion])
        }

        XCTAssertEqual(deleted, [])
        XCTAssertEqual(self.fixture.message(messageId)?.localTags.contains(.donutgramDeleted), true)
        XCTAssertEqual(self.fixture.message(messageId)?.localTags.contains(.donutgramHasEditHistory), true)
        XCTAssertEqual(self.fixture.message(messageId)?.text, "edited")
        let revisions = self.fixture.wait(donutgramMessageRevisions(postbox: self.fixture.postbox, messageId: messageId))
        XCTAssertEqual(revisions, [DonutgramMessageRevision(text: "saved", timestamp: self.baseDate)])
    }

    func testSavedDeletedMessagesDoNotRequestConfirmationAgain() {
        let peerId = self.seedUserChat(200)
        let messageId = self.storeSavedMessage(peerId: peerId, id: 32)

        self.fixture.transaction { transaction -> Void in
            guard let peer = transaction.getPeer(peerId) else {
                XCTFail("the chat is missing")
                return
            }
            let reconciliation = historyFillReconciliation(transaction: transaction, peer: peer, peerInput: .direct(peerId: peerId, threadId: nil), namespace: Namespaces.Message.Cloud, space: .everywhere, direction: .aroundId(messageId), filledRange: 1 ... 100, storeMessages: [])
            XCTAssertNil(reconciliation)
        }
    }

    private func checkSnapshotCandidateBudget(fromUpperBound: Bool, tag: MessageTags?, chatId: Int64) {
        let peerId = self.seedUserChat(chatId)
        let savedRange: ClosedRange<Int32> = fromUpperBound ? 206 ... 455 : 1 ... 250
        let unsavedRange: ClosedRange<Int32> = fromUpperBound ? 1 ... 205 : 251 ... 455
        let direction: MessageHistoryViewRelativeHoleDirection = .range(start: self.messageId(peerId, fromUpperBound ? 455 : 1), end: self.messageId(peerId, fromUpperBound ? 1 : 455))
        let tags: MessageTags = tag ?? []
        self.fixture.transaction { transaction -> Void in
            let messages = (Int32(1) ... Int32(455)).map { id -> StoreMessage in
                return StoreMessage(id: self.messageId(peerId, id), customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: self.baseDate + id, flags: [.Incoming], tags: tags, globalTags: [], localTags: savedRange.contains(id) ? [.donutgramDeleted] : [], forwardInfo: nil, authorId: peerId, text: "stored", attributes: [], media: [])
            }
            let _ = transaction.addMessages(messages, location: .Random)
            guard let peer = transaction.getPeer(peerId) else {
                XCTFail("the chat is missing")
                return
            }
            let seven = historyFillStoredIdsNearEdge(transaction: transaction, peerId: peerId, namespace: Namespaces.Message.Cloud, tag: tag, direction: direction, filledRange: 1 ... 455, limit: 7)
            let ordered = fromUpperBound ? Array(unsavedRange.reversed()) : Array(unsavedRange)
            XCTAssertEqual(seven.map { $0.id }, Array(ordered.prefix(7)))
            let reconciliation = historyFillReconciliation(transaction: transaction, peer: peer, peerInput: .direct(peerId: peerId, threadId: nil), namespace: Namespaces.Message.Cloud, space: tag.map { MessageHistoryHoleOperationSpace.tag($0) } ?? .everywhere, direction: direction, filledRange: 1 ... 455, storeMessages: [])
            XCTAssertEqual(reconciliation?.plan.batch.count, historyFillConfirmationLimit)
            XCTAssertEqual(reconciliation?.plan.batch.map { $0.id }, Array(ordered.prefix(historyFillConfirmationLimit)))
            XCTAssertEqual(reconciliation?.plan.closedRange, fromUpperBound ? 6 ... 455 : 1 ... 450)
            XCTAssertFalse(reconciliation?.plan.closedRange.contains(ordered[historyFillConfirmationLimit]) ?? true)
        }
    }

    func testSnapshotsDoNotExhaustUpwardCandidateBudget() {
        self.checkSnapshotCandidateBudget(fromUpperBound: false, tag: nil, chatId: 201)
    }

    func testSnapshotsDoNotExhaustDownwardCandidateBudget() {
        self.checkSnapshotCandidateBudget(fromUpperBound: true, tag: nil, chatId: 202)
    }

    func testTaggedSnapshotsDoNotExhaustUpwardCandidateBudget() {
        self.checkSnapshotCandidateBudget(fromUpperBound: false, tag: .pinned, chatId: 203)
    }

    func testTaggedSnapshotsDoNotExhaustDownwardCandidateBudget() {
        self.checkSnapshotCandidateBudget(fromUpperBound: true, tag: .pinned, chatId: 204)
    }

    func testAroundAnchorKeepsIndependentCandidateBudgetsPastSnapshots() {
        let peerId = self.seedUserChat(205)
        self.fixture.transaction { transaction -> Void in
            let messages = (Int32(1) ... Int32(1000)).map { id -> StoreMessage in
                return StoreMessage(id: self.messageId(peerId, id), customStableId: nil, globallyUniqueId: nil, groupingKey: nil, threadId: nil, timestamp: self.baseDate + id, flags: [.Incoming], tags: [.pinned], globalTags: [], localTags: (206 ... 795).contains(id) ? [.donutgramDeleted] : [], forwardInfo: nil, authorId: peerId, text: "stored", attributes: [], media: [])
            }
            let _ = transaction.addMessages(messages, location: .Random)
            let tags: [MessageTags?] = [nil, .pinned]
            for tag in tags {
                let ids = historyFillStoredIdsNearEdge(transaction: transaction, peerId: peerId, namespace: Namespaces.Message.Cloud, tag: tag, direction: .aroundId(self.messageId(peerId, 501)), filledRange: 1 ... 1000, limit: 7)
                XCTAssertEqual(ids.map { $0.id }, Array((Int32(199) ... Int32(205)).reversed()) + Array(Int32(796) ... Int32(802)))
                XCTAssertEqual(ids.count, 14)
            }
        }
    }
}
