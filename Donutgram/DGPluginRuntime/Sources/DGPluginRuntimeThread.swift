import Foundation
import Dispatch

/// The serial executor of one plugin runtime: a dedicated thread with a large stack.
///
/// QuickJS stops a runaway recursion only when its own stack limit (`JS_SetMaxStackSize`, 512 KiB here) is
/// reached before the real thread stack ends, and the C frames below and between its checks need room as well.
/// Dispatch worker threads have 512 KiB stacks, exactly the limit, so a deep recursion or a deeply nested
/// `JSON.parse` ran into the guard page and crashed the app. The message widget pool solves the same problem with
/// dedicated 8 MiB threads for a 2 MiB limit (`MessageWidgetPool.threadStackSize`).
///
/// Delays are measured on the monotonic uptime clock, so a change of the wall clock never stalls a runtime.
final class DGPluginRuntimeThread: @unchecked Sendable {
    static let stackSize = 4 * 1024 * 1024

    private struct Delayed {
        let due: UInt64
        let sequence: UInt64
        let work: () -> Void
    }

    private let lock = NSLock()
    private let wakeup = DispatchSemaphore(value: 0)
    private var immediate: [() -> Void] = []
    private var delayed: [Delayed] = []
    private var sequence: UInt64 = 0
    private var finishing = false
    private weak var thread: Thread?

    init(name: String) {
        // The thread keeps its executor alive until `finish()` lets the loop return.
        let thread = Thread { [self] in self.run() }
        thread.name = name
        thread.stackSize = DGPluginRuntimeThread.stackSize
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    func async(_ work: @escaping () -> Void) {
        self.lock.lock()
        self.immediate.append(work)
        self.lock.unlock()
        self.wakeup.signal()
    }

    func async(after delay: TimeInterval, _ work: @escaping () -> Void) {
        let nanoseconds = UInt64(max(0, delay) * 1_000_000_000)
        self.lock.lock()
        self.sequence &+= 1
        self.delayed.append(Delayed(due: DispatchTime.now().uptimeNanoseconds &+ nanoseconds, sequence: self.sequence, work: work))
        self.lock.unlock()
        self.wakeup.signal()
    }

    /// Runs `work` on the runtime thread and waits for it. Never call it from the runtime thread itself.
    func sync<T>(_ work: @escaping () -> T) -> T {
        precondition(Thread.current !== self.thread, "a plugin runtime thread cannot wait for itself")
        var result: T?
        let done = DispatchSemaphore(value: 0)
        self.async {
            result = work()
            done.signal()
        }
        done.wait()
        return result!
    }

    /// Runs the work already queued, drops pending delayed work and ends the thread.
    func finish() {
        self.lock.lock()
        self.finishing = true
        self.lock.unlock()
        self.wakeup.signal()
    }

    private func run() {
        while true {
            self.lock.lock()
            if !self.immediate.isEmpty {
                let work = self.immediate.removeFirst()
                self.lock.unlock()
                Self.perform(work)
                continue
            }
            if self.finishing {
                self.delayed.removeAll()
                self.lock.unlock()
                return
            }
            var nextIndex: Int?
            for index in self.delayed.indices {
                if let current = nextIndex {
                    let candidate = self.delayed[index], best = self.delayed[current]
                    if candidate.due < best.due || (candidate.due == best.due && candidate.sequence < best.sequence) { nextIndex = index }
                } else {
                    nextIndex = index
                }
            }
            guard let index = nextIndex else {
                self.lock.unlock()
                self.wakeup.wait()
                continue
            }
            let due = self.delayed[index].due
            if due <= DispatchTime.now().uptimeNanoseconds {
                let work = self.delayed.remove(at: index).work
                self.lock.unlock()
                Self.perform(work)
                continue
            }
            self.lock.unlock()
            _ = self.wakeup.wait(timeout: DispatchTime(uptimeNanoseconds: due))
        }
    }

    private static func perform(_ work: () -> Void) {
        #if canImport(ObjectiveC)
        autoreleasepool { work() }
        #else
        work()
        #endif
    }
}
