import Foundation
import DGPluginModel
import DGPluginViewAdapters
import MergeLists

private struct Row: Comparable, MergeLists.Identifiable {
    let stableId: Int
    let native: Int
    let local: Int?
    static func < (lhs: Row, rhs: Row) -> Bool {
        if let left = lhs.local, let right = rhs.local { return left < right }
        return lhs.native < rhs.native
    }
}

@main
struct DGPluginViewAdapterChecks {
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw DGPluginError(code: "test_failure", message: message) }
    }

    static func orders(_ values: [Int]) -> [[Int]] {
        var result: [[Int]] = []
        for (index, value) in values.enumerated() {
            result.append([value])
            var remaining = values
            remaining.remove(at: index)
            result += orders(remaining).map { [value] + $0 }
        }
        return result
    }

    static func notificationChecks() throws {
        let store = DGPluginNotificationStore(limit: 3)
        for index in 0..<1000 {
            let identifier = store.identifierPrefix + String(index)
            let snapshot = store.snapshot()
            store.reconcile(snapshot: snapshot, pending: [], delivered: snapshot)
            try require(store.reserve(identifier), "successful notifications exhausted the resource limit")
            try require(store.scheduled(identifier), "successful notification was lost")
            try require(store.snapshot().count <= 3, "notification memory grew beyond its bound")
        }
        let cancelled = store.cancel()
        try require(Set(cancelled) == Set((997..<1000).map { store.identifierPrefix + String($0) }), "scope stop lost retained notifications")
        let replacement = DGPluginNotificationStore(limit: 3)
        let delivered = (0..<1000).map { store.identifierPrefix + String($0) }
        let foreign = [replacement.identifierPrefix + "new", "telegram.native", "donutgram.plugin.unrelated"]
        let centerIdentifiers = delivered + foreign
        let removed = centerIdentifiers.filter { store.owns($0) }
        try require(removed == delivered, "scope stop could not find forgotten delivered notifications")
        try require(centerIdentifiers.filter { !store.owns($0) } == foreign, "late cancellation removed another scope or native notification")
        try require(!store.owns(String(store.identifierPrefix.dropLast())), "scope identifier boundary was not enforced")
        try require(!store.reserve("after-close"), "closed scope admitted a notification")
        try require(store.cancel().isEmpty, "scope stop cancelled notifications twice")
        let pending = DGPluginNotificationStore(limit: 2)
        try require(pending.reserve("pending") && pending.scheduled("pending"), "pending notification was not retained")
        try require(pending.reserve("adding"), "in-flight notification was rejected")
        let snapshot = pending.snapshot()
        pending.reconcile(snapshot: snapshot, pending: ["pending"], delivered: [])
        try require(!pending.reserve("overflow"), "pending notification limit was bypassed")
        try require(pending.scheduled("adding"), "snapshot discarded an in-flight notification")
        pending.reconcile(snapshot: snapshot, pending: [], delivered: [])
        try require(pending.snapshot() == ["adding"], "snapshot removed a newer notification or retained a vanished one")
        try require(pending.reserve("racing-add"), "expired pending quota was not reclaimed")
        try require(Set(pending.cancel()) == ["adding", "racing-add"], "chat close did not cancel pending and in-flight requests")
        try require(!pending.scheduled("racing-add"), "late add completion revived a cancelled request")
        pending.reconcile(snapshot: ["adding"], pending: ["adding"], delivered: [])
        try require(pending.snapshot().isEmpty, "late center response revived a cancelled request")
        let failed = DGPluginNotificationStore(limit: 1)
        try require(failed.reserve("failed"), "failed request reservation was rejected")
        failed.remove("failed")
        try require(failed.reserve("retry"), "failed authorization or add consumed quota")
        print("passed notification retention, pending quota and close/add race checks")
    }

    static func main() throws {
        try notificationChecks()
        let lifetime = DGPluginChatLifetime()
        try require(!lifetime.snapshot()(), "closed chat accepted an operation")
        lifetime.open()
        let firstVisit = lifetime.snapshot()
        try require(firstVisit(), "open chat rejected an operation")
        lifetime.close()
        try require(!firstVisit(), "closed chat kept a pending operation")
        lifetime.open()
        try require(!firstVisit() && lifetime.snapshot()(), "reopened chat revived a stale operation")
        let secondVisit = lifetime.snapshot()
        let pendingAcrossReopen = UUID()
        var reopenCancelled = false
        lifetime.own(pendingAcrossReopen) { reopenCancelled = true }
        lifetime.open()
        try require(secondVisit() && !reopenCancelled, "opening an open chat (a cancelled swipe back) cancelled its operations")
        lifetime.release(pendingAcrossReopen)
        var cancelledResources = 0
        let finishedResource = UUID()
        lifetime.own(finishedResource) { cancelledResources += 100 }
        lifetime.release(finishedResource)
        lifetime.own(UUID()) { cancelledResources += 1 }
        lifetime.own(UUID()) { cancelledResources += 1 }
        lifetime.close()
        try require(cancelledResources == 2, "chat close did not cancel all pending resources exactly once")
        lifetime.close()
        try require(cancelledResources == 2, "chat close cancelled resources twice")
        lifetime.own(UUID()) { cancelledResources += 1 }
        try require(cancelledResources == 3, "closed chat retained a new resource")
        var abandoned: DGPluginChatLifetime? = DGPluginChatLifetime()
        abandoned?.open()
        abandoned?.own(UUID()) { cancelledResources += 1 }
        abandoned = nil
        try require(cancelledResources == 4, "chat destruction retained a pending resource")
        var now = 100.0
        let confirmation = DGPluginConfirmationState(timeout: 45, clock: { now })
        try require(confirmation.isCurrent() && confirmation.accept(), "fresh confirmation was unavailable")
        try require(!confirmation.accept(), "confirmation accepted twice")
        now = 146
        try require(!confirmation.isCurrent(), "accepted confirmation survived timeout")
        try require(confirmation.finish() && !confirmation.finish(), "confirmation completed twice")
        let cancelled = DGPluginConfirmationState()
        try require(cancelled.finish() && !cancelled.accept() && !cancelled.isCurrent(), "cancelled confirmation remained current")
        let rows = [DGPluginLocalChatRow(handle: "pinned.1", title: "pin", unread: 0, pinned: true), DGPluginLocalChatRow(handle: "a", title: "a", unread: 1, pinned: false), DGPluginLocalChatRow(handle: "b", title: "b", unread: 2, pinned: false)]
        let reordered = DGPluginJSON.object(["items": .array([rows[0].json, rows[2].json, rows[1].json])])
        try require(DGPluginLocalChatProjection.handles(rows: rows, output: reordered) == ["pinned.1", "b", "a"], "local order rejected")
        try require(DGPluginLocalChatProjection.handles(rows: rows, output: .object(["items": .array([rows[1].json])])) == nil, "pinned row was hidden")
        try require(DGPluginLocalChatProjection.handles(rows: rows, output: .object(["items": .array([rows[1].json, rows[0].json])])) == nil, "pinned row was moved")
        try require(DGPluginLocalChatProjection.handles(rows: rows, output: .object(["items": .array([rows[0].json, rows[1].json, rows[1].json])])) == nil, "duplicate handle was accepted")
        try require(DGPluginLocalChatProjection.handles(rows: rows, output: .object(["items": .array([rows[0].json])])) == ["pinned.1", "a"], "last local anchor was lost")
        let unknown = DGPluginLocalChatRow(handle: "unknown", title: "unknown", unread: 0, pinned: false)
        try require(DGPluginLocalChatProjection.handles(rows: rows, output: .object(["items": .array([rows[0].json, unknown.json])])) == nil, "unknown row was introduced")
        var altered = rows[1].json.objectValue!
        altered["title"] = .string("replacement")
        try require(DGPluginLocalChatProjection.handles(rows: rows, output: .object(["items": .array([rows[0].json, .object(altered)])])) == nil, "native title was replaced")
        let bounded = DGPluginLocalChatRow(handle: "bounded", title: String(repeating: "x", count: 10000), unread: Int.max, pinned: false)
        try require(bounded.title.utf16.count == 128 && bounded.unread == 1000000, "snapshot was not bounded")
        try require(DGPluginEmptyPaneProjection.ids(source: ["stories", "gifts"], knownEmpty: ["stories"], requested: ["gifts"]) == ["gifts"], "known empty pane was not filtered")
        try require(DGPluginEmptyPaneProjection.ids(source: ["stories", "gifts"], knownEmpty: [], requested: []) == ["stories", "gifts"], "unknown counts were treated as empty")
        try require(DGPluginEmptyPaneProjection.ids(source: ["stories"], knownEmpty: ["stories"], requested: []) == ["stories"], "all profile controls were hidden")
        let native = (0..<4).map { Row(stableId: $0, native: $0, local: nil) } + [Row(stableId: 100, native: 100, local: nil), Row(stableId: 101, native: 101, local: nil)]
        let states = [native] + orders(Array(0..<4)).map { order in
            order.enumerated().map { Row(stableId: $0.element, native: $0.element, local: $0.offset) } + native.suffix(2)
        }
        var transitions = 0
        for left in states {
            for right in states {
                let (deleted, inserted, updated) = mergeListsStableWithUpdates(leftList: left, rightList: right)
                var actual = left
                for index in deleted.reversed() { actual.remove(at: index) }
                for (index, item, _) in inserted { actual.insert(item, at: index) }
                for (index, item, _) in updated { actual[index] = item }
                try require(actual == right, "native stable merge did not reproduce local ordering")
                try require(Array(actual.suffix(2)) == Array(native.suffix(2)), "pinned/header data changed")
                transitions += 1
            }
        }
        print("passed 24 native projection/confirmation checks and \(transitions) real stable-merge transitions")
    }
}
