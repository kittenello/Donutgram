import Foundation

public final class DGPluginChatLifetime {
    private let lock = NSLock()
    private var generation: UUID?
    private var cleanup: [UUID: () -> Void] = [:]

    public init() {}

    /// Opening a chat that is already open changes nothing. A swipe back that the user cancels ends with
    /// viewDidAppear alone, and it must not cancel what plugins are doing in the chat.
    public func open() {
        self.lock.lock()
        if self.generation == nil { self.generation = UUID() }
        self.lock.unlock()
    }

    public func close() {
        self.lock.lock()
        self.generation = nil
        let cleanup = Array(self.cleanup.values)
        self.cleanup.removeAll()
        self.lock.unlock()
        cleanup.forEach { $0() }
    }

    public func own(_ token: UUID, cleanup: @escaping () -> Void) {
        self.lock.lock()
        if self.generation != nil {
            self.cleanup[token] = cleanup
            self.lock.unlock()
        } else {
            self.lock.unlock()
            cleanup()
        }
    }

    public func release(_ token: UUID) {
        self.lock.lock()
        self.cleanup.removeValue(forKey: token)
        self.lock.unlock()
    }

    public func snapshot() -> () -> Bool {
        self.lock.lock()
        let expected = self.generation
        self.lock.unlock()
        return { [weak self] in
            guard let self, let expected else { return false }
            self.lock.lock()
            defer { self.lock.unlock() }
            return self.generation == expected
        }
    }

    deinit {
        self.cleanup.values.forEach { $0() }
    }
}
