func check(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}

func wait(_ semaphore: DispatchSemaphore, _ message: String) {
    check(semaphore.wait(timeout: .now() + 2) == .success, message)
}

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
print("plugin document ordering, validation/download deadlines, errors and cancellation passed")
