import Foundation

enum EngineMessage {
    struct Id: Hashable, Comparable {
        let peerId: Int64
        let id: Int32

        static func <(lhs: Id, rhs: Id) -> Bool {
            return (lhs.peerId, lhs.id) < (rhs.peerId, rhs.id)
        }
    }
}

// PRODUCTION_HELPERS

var failures = 0

func check(_ condition: Bool, _ message: String, line: Int = #line) {
    if !condition {
        print("FAIL line \(line): \(message)")
        failures += 1
    }
}

func entry(_ id: Int32, _ text: String) -> DonutgramPreservedMessageSearchEntry {
    return DonutgramPreservedMessageSearchEntry(id: EngineMessage.Id(peerId: 101, id: id), timestamp: id, text: text)
}

func ids(_ query: String, _ entries: [DonutgramPreservedMessageSearchEntry], limit: Int = 10, isCancelled: () -> Bool = { false }) -> [Int32] {
    return donutgramPreservedMessageIds(matching: query, in: entries, limit: limit, isCancelled: isCancelled).map { $0.id }
}

// Matching: whole words by prefix, any case, ё = е, file names split at dots and underscores.
check(donutgramDeletedMessageMatchesQuery(text: "Фото с отпуска", query: "ФОТО отп"), "case and prefixes")
check(donutgramDeletedMessageMatchesQuery(text: "Годовой отчёт report_2026.pdf", query: "ОТЧЕТ rep pdf"), "ё and file name")
check(!donutgramDeletedMessageMatchesQuery(text: "Годовой отчёт", query: "отчёт январь"), "every query word must match")
check(!donutgramDeletedMessageMatchesQuery(text: "фотография", query: "графия"), "no infix matches")
check(donutgramDeletedMessageMatchesQuery(text: "", query: ""), "empty query matches in a chat")

// The index folds each text once, into distinct words.
check(entry(1, "Отчёт.PDF отчёт").words.sorted() == ["pdf", "отчет"], "folded distinct words")
check(entry(2, " ?! ").words.isEmpty, "no words without letters or digits")

// The page: order of the index, limit, and nothing for a query without words.
let entries = [entry(30, "Встреча завтра"), entry(20, "привет"), entry(10, "ВСТРЕЧА в офисе отчёт.pdf")]
check(ids("встр", entries) == [30, 10], "order kept")
check(ids("встреча", entries, limit: 1) == [30], "limit")
check(ids("отчет pdf", entries) == [10], "several words")
check(ids("пока", entries) == [], "no match")
check(ids("", entries) == [], "empty query matches nothing on the page")
check(ids(" ?! ", entries) == [], "query without words matches nothing on the page")

// One more than the page shows tells it the list is cut.
let many = (1 ... 300).map { entry(Int32(301 - $0), "встреча \($0)") }
check(ids("встреча", many, limit: 201).count == 201, "limit + 1 found when more match")
check(ids("встреча 7", many, limit: 201).count < 201, "fewer found when fewer match")

// A superseded scan stops early.
var polls = 0
let stopped = ids("встреча", many, limit: 1000, isCancelled: {
    polls += 1
    return polls > 1
})
check(stopped.count == 256, "scan stops at the next poll, got \(stopped.count)")
check(ids("встреча", many, limit: 1000, isCancelled: { true }) == [], "cancelled before the first entry")

if failures > 0 {
    exit(1)
}
print("Deleted messages search checks passed.")
