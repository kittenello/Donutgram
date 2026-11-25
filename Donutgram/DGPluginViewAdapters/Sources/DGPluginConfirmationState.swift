import Foundation

public final class DGPluginConfirmationState {
    private let lock = NSLock()
    private let expires: TimeInterval
    private let clock: () -> TimeInterval
    private var completed = false
    private var accepted = false

    public init(timeout: TimeInterval = 45, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
        self.expires = clock() + timeout
    }

    public func isCurrent() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        return !self.completed && self.clock() <= self.expires
    }

    public func accept() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard !self.completed, !self.accepted, self.clock() <= self.expires else { return false }
        self.accepted = true
        return true
    }

    public func finish() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard !self.completed else { return false }
        self.completed = true
        return true
    }
}
