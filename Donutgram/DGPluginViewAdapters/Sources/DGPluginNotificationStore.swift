import Foundation

public final class DGPluginNotificationStore {
    public static let identifierNamespace = "donutgram.plugin."
    public let identifierPrefix = DGPluginNotificationStore.identifierNamespace + UUID().uuidString.lowercased() + "."

    /// True for a notification some plugin scheduled, whichever store owns it.
    public static func isPluginNotification(_ identifier: String) -> Bool { identifier.hasPrefix(identifierNamespace) }

    public func owns(_ identifier: String) -> Bool { identifier.hasPrefix(identifierPrefix) }

    private enum State { case submitting, pending, delivered }
    private let lock = NSLock()
    private var active = true
    private var states: [String: State] = [:]
    private var order: [String] = []
    private let limit: Int

    public init(limit: Int = 16) { self.limit = max(1, limit) }

    public func snapshot() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(states.compactMap { $0.value == .submitting ? nil : $0.key })
    }

    public func reconcile(snapshot: Set<String>, pending: Set<String>, delivered: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        for identifier in snapshot where states[identifier] != nil && states[identifier] != .submitting {
            if pending.contains(identifier) { states[identifier] = .pending }
            else if delivered.contains(identifier) { states[identifier] = .delivered }
            else { states.removeValue(forKey: identifier) }
        }
        order.removeAll { states[$0] == nil }
    }

    public func reserve(_ identifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard active, states[identifier] == nil, states.values.filter({ $0 != .delivered }).count < limit else { return false }
        if states.count >= limit, let oldest = order.first(where: { states[$0] == .delivered }) {
            states.removeValue(forKey: oldest)
            order.removeAll { $0 == oldest }
        }
        states[identifier] = .submitting
        order.append(identifier)
        return true
    }

    public func scheduled(_ identifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard active, states[identifier] == .submitting else { return false }
        states[identifier] = .pending
        return true
    }

    public func remove(_ identifier: String) {
        lock.lock()
        states.removeValue(forKey: identifier)
        order.removeAll { $0 == identifier }
        lock.unlock()
    }

    public func cancel() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        active = false
        let identifiers = order
        states.removeAll()
        order.removeAll()
        return identifiers
    }
}
