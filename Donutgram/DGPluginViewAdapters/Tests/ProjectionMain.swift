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

    static func main() throws {
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
        print("passed 16 native projection/confirmation checks and \(transitions) real stable-merge transitions")
    }
}
