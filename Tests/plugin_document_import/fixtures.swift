func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}

func pluginSearchKeepsInputBeforeTheNextListUpdate() {
    let page = DGPluginInputFixture()
    let row = DGPluginRow(index: 0, section: 1, kind: .input, key: "search", title: "Search")
    let input = row.inputCallback(page: page)
    input("а")
    input("ав")
    input("автозамена")
    check(page.query == "автозамена", "search lost text while the list was applying its previous update")
    page.refresh()
    input("курсы")
    check(page.query == "курсы", "an unrelated manager refresh dropped search input")
    page.busy = true
    input("busy")
    check(page.query == "курсы", "busy page accepted search input")
    page.busy = false
    page.mode = .other
    var current = row
    current.epoch = page.sequence
    current.inputCallback(page: page)("wrong page")
    check(page.query == "курсы", "search input escaped its list page")
    page.mode = .settings
    check(page.acceptsInput(row.epoch, "setting:replacement"), "native setting input was dropped during a list update")
    check(!page.acceptsInput(row.epoch, "render:field"), "stale plugin-rendered input bypassed its page revision")
    check(page.acceptsInput(page.sequence, "render:field"), "current plugin-rendered input was rejected")
    page.busy = true
    check(!page.acceptsInput(row.epoch, "setting:replacement"), "busy page accepted native setting input")
    page.busy = false
    page.mode = .other
    check(!page.acceptsInput(page.sequence, "setting:replacement"), "native setting input escaped its settings page")
    print("plugin rapid text input, page ownership, busy state and rendered revision guards passed")
}

pluginSearchKeepsInputBeforeTheNextListUpdate()

func pluginListSearchAndPauseTransitions() {
    let page = DGPluginListFixture()
    let installations = (0 ..< 6).map { index in
        DGPluginInstallation(id: "installation-\(index)", manifest: DGPluginManifest(id: "dev.example.plugin\(index)", name: "plugin\(index)", version: "1.0.0", description: "fixture"), digest: "digest-\(index)", trust: "local", enabled: index == 0, state: index == 0 ? .running : .installedDisabled)
    }
    for count in 0 ... 6 {
        page.manager.installations = Array(installations.prefix(count))
        page.query = ""
        let rows = page.rows()
        check(rows.filter { $0.key == "search" }.count == (count >= 5 ? 1 : 0), "search threshold must use the installed count")
        check(rows.filter { $0.kind == .header && $0.title == "INSTALLED" }.count == 1, "installed header must remain visible")
        check(rows.filter { $0.kind == .plugin }.count == count, "unfiltered plugin list lost a card")
        check(!rows.contains { $0.kind == .text }, "empty or unfiltered list gained an installation hint")
        check(rows.first { $0.key == "global" }?.detail == "", "global switch gained a pause or count subtitle")
    }
    page.manager.installations = Array(installations.prefix(5))
    page.query = "plugin0"
    let active = page.rows()
    check(active.filter { $0.kind == .plugin }.count == 1, "search must filter cards")
    check(active.contains { $0.key == "search" }, "filtering to one result hid the search field")
    page.manager.globallyEnabled = false
    let paused = page.rows()
    let pausedCard = paused.first { $0.kind == .plugin }!
    check(pausedCard.value && !pausedCard.toggleEnabled && pausedCard.enabled, "pause must lock the switch while preserving saved enablement and card actions")
    check(pausedCard.detail == "Author not specified · 1.0.0", "card repeats the global pause status")
    let transition = mergeListsStableWithUpdates(leftList: active, rightList: paused, isLess: { $0 < $1 }, isEqual: { $0 == $1 }, getId: { AnyHashable($0.stableId) })
    check(transition.2.contains { $0.1.kind == .plugin && !$0.1.toggleEnabled }, "list diff missed a switch-only change")
    page.manager.globallyEnabled = true
    let resumed = page.rows().first { $0.kind == .plugin }!
    check(resumed.value && resumed.toggleEnabled && resumed.enabled, "resume must unlock the saved switch")
    page.query = "no such plugin"
    let noMatches = page.rows()
    check(noMatches.contains { $0.key == "search" }, "empty search results hid the search field")
    check(noMatches.contains { $0.kind == .text && $0.title == "Nothing found" }, "active search lost its no-results message")
    page.manager.installations.removeLast()
    let afterRemoval = page.rows()
    check(page.query.isEmpty, "hidden search retained its old filter after removal")
    check(!afterRemoval.contains { $0.key == "search" }, "search stayed visible below five installed plugins")
    check(afterRemoval.filter { $0.kind == .plugin }.count == 4, "hidden search filtered the remaining plugins")
    page.manager.installations = []
    check(page.rows().map { $0.kind } == [.toggle, .header], "empty list must retain only the global switch and installed header")
    print("plugin list thresholds, empty results, removal, pause/resume and switch-only diffs passed")
}

pluginListSearchAndPauseTransitions()

func wait(_ semaphore: DispatchSemaphore, _ message: String) {
    check(semaphore.wait(timeout: .now() + 2) == .success, message)
}

func pluginRowsReplaceIncompatibleNodes() {
    let loading = DGPluginRow(index: 0, section: 0, kind: .text, key: "", title: "preparing")
    let card = DGPluginRow(index: 0, section: 0, kind: .card, key: "", title: "message tools")
    let old = mergeListsStableWithUpdates(leftList: [loading], rightList: [card], isLess: { $0.index < $1.index }, isEqual: { $0 == $1 }, getId: { AnyHashable($0.index) })
    check(old.0.isEmpty && old.1.isEmpty && old.2.count == 1, "old positional identity reuses the text node for a card and stalls updateNode")
    let fixed = mergeListsStableWithUpdates(leftList: [loading], rightList: [card], isLess: { $0 < $1 }, isEqual: { $0 == $1 }, getId: { AnyHashable($0.stableId) })
    check(fixed.0 == [0] && fixed.1.count == 1 && fixed.2.isEmpty, "card must get a new node, not update the loading text node")
    var updated = card
    updated.epoch = 1
    let contentUpdate = mergeListsStableWithUpdates(leftList: [card], rightList: [updated], isLess: { $0 < $1 }, isEqual: { $0 == $1 }, getId: { AnyHashable($0.stableId) })
    check(contentUpdate.0.isEmpty && contentUpdate.1.isEmpty && contentUpdate.2.count == 1, "same-kind content refresh should retain its node")
    var rows: [DGPluginRow] = []
    for index in 0 ..< 8 {
        var kind: Int32 = 0
        while let value = DGPluginRow.Kind(rawValue: kind) {
            rows.append(DGPluginRow(index: Int32(index), section: 0, kind: value, key: "", title: ""))
            kind += 1
        }
    }
    check(Set(rows.map { $0.stableId }).count == rows.count, "different row positions and node kinds must have unique identities")
    check(rows == rows.sorted(), "row identity must preserve display order")
    print("reproduced: positional identity reuses incompatible list nodes; production identity replaces them")
}

func documentOperationFinishesOnce() {
    var events: [String] = []
    let operation = DGPluginDocumentOperation<String> { result in
        if let result, case .success = result { events.append("show card") }
        else { events.append("dismiss") }
    }
    operation.disposable.set(ActionDisposable { events.append("dispose fetch") })
    operation.finish(nil)
    operation.finish(.success("late result"))
    check(events == ["dispose fetch", "dismiss"], "cancellation must dismiss once, dispose the fetch and reject late cards")
    let synchronous = DGPluginDocumentOperation<String> { _ in events.append("ready") }
    synchronous.finish(.success("cached attachment"))
    synchronous.disposable.set(ActionDisposable { events.append("dispose synchronous subscription") })
    synchronous.finish(nil)
    check(events.suffix(2) == ["ready", "dispose synchronous subscription"], "synchronous result must not leak its subsequently assigned disposable")
}

pluginRowsReplaceIncompatibleNodes()
documentOperationFinishesOnce()

func oldConcurrentDeliveryDropsValidatedData() {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let validationDone = DispatchSemaphore(value: 0)
    let completed = DispatchSemaphore(value: 0)
    let values = Atomic<[String]>(value: [])
    let disposable = (Signal<String, NoError>.single("attachment")
    |> deliverOn(Queue.concurrentDefaultQueue())
    |> map { value -> String in
        entered.signal()
        wait(release, "old validation release")
        validationDone.signal()
        return value
    }).start(next: { value in let _ = values.modify { $0 + [value] } }, completed: { completed.signal() })
    wait(entered, "old validation started")
    wait(completed, "old completion overtook validation")
    release.signal()
    wait(validationDone, "old validation finished")
    check(values.with { $0.isEmpty }, "old concurrent pipeline should reproduce the lost result")
    disposable.dispose()
    print("reproduced: concurrent completion drops attachment validation result")
}

func serialValidationDeliversBeforeCompletion() {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)
    let completed = DispatchSemaphore(value: 0)
    let events = Atomic<[String]>(value: [])
    let disposable = dgPluginValidateDocument(source: Signal<String, NoError>.single("attachment"), timeout: 1, validate: { value in
        entered.signal()
        wait(release, "serial validation release")
        return value
    }).start(next: { result in
        guard case let .success(value) = result else { fatalError("valid attachment unexpectedly rejected") }
        let _ = events.modify { $0 + [value] }
    }, completed: {
        let _ = events.modify { $0 + ["complete"] }
        completed.signal()
    })
    wait(entered, "serial validation started")
    check(events.with { $0.isEmpty }, "completion must wait for validation")
    release.signal()
    wait(completed, "serial validation completed")
    check(events.with { $0 == ["attachment", "complete"] }, "validated data must precede completion")
    disposable.dispose()
}

func expectFailure(_ signal: Signal<Result<String, DGPluginError>, NoError>, code: String) {
    let completed = DispatchSemaphore(value: 0)
    let values = Atomic<[String]>(value: [])
    let disposable = signal.start(next: { result in
        guard case let .failure(error) = result else { fatalError("failure unexpectedly succeeded") }
        let _ = values.modify { $0 + [error.code] }
    }, completed: { completed.signal() })
    wait(completed, "failure path must leave loading state")
    check(values.with { $0 == [code] }, "failure must be delivered once with its actual code")
    disposable.dispose()
}

oldConcurrentDeliveryDropsValidatedData()
for _ in 0 ..< 20 { serialValidationDeliversBeforeCompletion() }
expectFailure(dgPluginValidateDocument(source: Signal<String, NoError>.never(), timeout: 0.05, validate: { $0 }), code: "validation_timeout")
expectFailure(dgPluginValidateDocument(source: Signal<String, NoError>.complete(), timeout: 0.05, validate: { $0 }), code: "download_failed")
expectFailure(dgPluginValidateDocument(source: Signal<String, NoError>.single("bad"), validate: { _ -> String in throw DGPluginError(code: "invalid_manifest", message: "bad package") }), code: "invalid_manifest")

let entered = DispatchSemaphore(value: 0)
let release = DispatchSemaphore(value: 0)
let finished = DispatchSemaphore(value: 0)
let timedOut = DispatchSemaphore(value: 0)
let lateResults = Atomic<[String]>(value: [])
let slow = dgPluginValidateDocument(source: Signal<String, NoError>.single("slow"), timeout: 0.05, validate: { value in
    entered.signal()
    wait(release, "slow validation release")
    finished.signal()
    return value
}).start(next: { result in
    switch result {
    case .success: let _ = lateResults.modify { $0 + ["success"] }
    case let .failure(error): let _ = lateResults.modify { $0 + [error.code] }
    }
}, completed: { timedOut.signal() })
wait(entered, "slow validation started")
wait(timedOut, "deadline must include validation, not only download")
release.signal()
wait(finished, "slow validator released after timeout")
check(lateResults.with { $0 == ["validation_timeout"] }, "late validation must not replace timeout")
slow.dispose()

let cancelledStarted = DispatchSemaphore(value: 0)
let cancelledRelease = DispatchSemaphore(value: 0)
let cancelledDone = DispatchSemaphore(value: 0)
let cancelled = dgPluginValidateDocument(source: Signal<String, NoError>.single("cancel"), validate: { value in
    cancelledStarted.signal()
    wait(cancelledRelease, "cancelled validation release")
    cancelledDone.signal()
    return value
}).start(next: { _ in fatalError("closed preview received a result") }, completed: { fatalError("closed preview received completion") })
wait(cancelledStarted, "cancelled validator started")
cancelled.dispose()
cancelledRelease.signal()
wait(cancelledDone, "cancelled validator released")
Thread.sleep(forTimeInterval: 0.02)
check(lateResults.with { $0 == ["validation_timeout"] }, "late validation output must remain rejected after the worker drains")
print("plugin document node transitions, operation lifetime, ordering, validation/download deadlines, errors and cancellation passed")
