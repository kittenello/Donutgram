import XCTest
import Postbox
import TelegramCore

final class DeletedMessageSearchTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(101))

    private func message(_ id: Int32, deleted: Bool = false) -> Message {
        return Message(stableId: UInt32(id), stableVersion: deleted ? 1 : 0, id: MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: id), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: id, flags: [.Incoming], tags: [], globalTags: [], localTags: deleted ? [.donutgramDeleted] : [], customTags: [], forwardInfo: nil, author: nil, text: "message \(id)", attributes: [], media: [], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func result(_ ids: [Int32], totalCount: Int32, completed: Bool) -> SearchMessagesResult {
        return SearchMessagesResult(messages: ids.map { self.message($0) }, readStates: [:], threadInfo: [:], totalCount: totalCount, completed: completed)
    }

    func testRussianCaseAndFileNamePrefixes() {
        XCTAssertTrue(donutgramDeletedMessageMatchesQuery(text: "Фото с отпуска", query: "ФОТО отп"))
        XCTAssertTrue(donutgramDeletedMessageMatchesQuery(text: "Годовой отчёт report_2026.pdf", query: "ОТЧЕТ rep pdf"))
        XCTAssertFalse(donutgramDeletedMessageMatchesQuery(text: "Годовой отчёт", query: "отчёт январь"))
        XCTAssertFalse(donutgramDeletedMessageMatchesQuery(text: "фотография", query: "графия"))
        XCTAssertTrue(donutgramDeletedMessageMatchesQuery(text: "", query: ""))
    }

    func testOldDeletionsWaitForTheirServerPage() {
        let local = [self.message(90, deleted: true), self.message(10, deleted: true)]
        let first = donutgramSearchResultIncludingDeletedMessages(self.result([100, 80], totalCount: 4, completed: false), deletedMessages: local)
        XCTAssertEqual(first.messages.map { $0.id.id }, [100, 90, 80])
        XCTAssertEqual(first.totalCount, 6)
        XCTAssertFalse(first.completed)

        let last = donutgramSearchResultIncludingDeletedMessages(self.result([100, 80, 60, 20], totalCount: 4, completed: true), deletedMessages: local)
        XCTAssertEqual(last.messages.map { $0.id.id }, [100, 90, 80, 60, 20, 10])
        XCTAssertEqual(last.totalCount, 6)
        XCTAssertTrue(last.completed)
    }

    func testDuplicateIdsUsePreservedMessageWithoutInflatingCount() {
        let deleted = self.message(80, deleted: true)
        let merged = donutgramSearchResultIncludingDeletedMessages(self.result([100, 80], totalCount: 2, completed: true), deletedMessages: [deleted, deleted])
        XCTAssertEqual(merged.messages.map { $0.id.id }, [100, 80])
        XCTAssertEqual(merged.totalCount, 2)
        XCTAssertTrue(merged.messages[1].localTags.contains(.donutgramDeleted))
    }

    func testSavedDeletedPageSearchKeepsOrderAndLimit() {
        let entries = [
            DonutgramPreservedMessageSearchEntry(id: MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 30), timestamp: 30, text: "Встреча завтра"),
            DonutgramPreservedMessageSearchEntry(id: MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 20), timestamp: 20, text: "привет"),
            DonutgramPreservedMessageSearchEntry(id: MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 10), timestamp: 10, text: "ВСТРЕЧА в офисе отчёт.pdf")
        ]
        XCTAssertEqual(donutgramPreservedMessageIds(matching: "встр", in: entries, limit: 10).map { $0.id }, [30, 10])
        XCTAssertEqual(donutgramPreservedMessageIds(matching: "встреча", in: entries, limit: 1).map { $0.id }, [30])
        XCTAssertEqual(donutgramPreservedMessageIds(matching: "отчет pdf", in: entries, limit: 10).map { $0.id }, [10])
        XCTAssertEqual(donutgramPreservedMessageIds(matching: "пока", in: entries, limit: 10), [])
    }

    func testSavedDeletedPageSearchIgnoresQueryWithoutWords() {
        let entries = [DonutgramPreservedMessageSearchEntry(id: MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 1), timestamp: 1, text: "что угодно")]
        XCTAssertEqual(donutgramPreservedMessageIds(matching: "", in: entries, limit: 10), [])
        XCTAssertEqual(donutgramPreservedMessageIds(matching: " ?! ", in: entries, limit: 10), [])
    }

    func testLocalOnlyResultsOnEmptyRemoteResponse() {
        let merged = donutgramSearchResultIncludingDeletedMessages(self.result([], totalCount: 0, completed: true), deletedMessages: [self.message(4, deleted: true), self.message(9, deleted: true)])
        XCTAssertEqual(merged.messages.map { $0.id.id }, [9, 4])
        XCTAssertEqual(merged.totalCount, 2)
        XCTAssertTrue(merged.completed)
    }
}
