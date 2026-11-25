import Foundation
import DGPluginModel

public final class DGPluginNativeActionStore {
    private struct Action {
        let scope: String
        let recipient: String
        let text: String
        let expires: TimeInterval
    }
    private let lock = NSLock()
    private var actions: [String: Action] = [:]

    public init() {}

    public func prepare(scope: String, recipient: String, text: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) throws -> String {
        guard !scope.isEmpty, !recipient.isEmpty, !text.isEmpty, text.utf16.count <= 4096 else { throw DGPluginError(code: "invalid_argument", message: "invalid ordinary text message") }
        lock.lock(); defer { lock.unlock() }
        actions = actions.filter { $0.value.expires >= now }
        guard actions.count < 8 else { throw DGPluginError(code: "quota_exceeded", message: "too many pending native actions") }
        let handle = UUID().uuidString.lowercased()
        actions[handle] = Action(scope: scope, recipient: recipient, text: text, expires: now + 45)
        return handle
    }

    public func preview(handle: String, scope: String, recipient: String, now: TimeInterval = ProcessInfo.processInfo.systemUptime) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard let action = actions[handle], action.scope == scope, action.recipient == recipient, now <= action.expires else { throw DGPluginError(code: "stale_handle", message: "native message preview expired or changed recipient") }
        return action.text
    }

    public func consume(handle: String, scope: String, recipient: String, paidRecipient: Bool, now: TimeInterval = ProcessInfo.processInfo.systemUptime) throws -> String {
        lock.lock(); defer { lock.unlock() }
        guard let action = actions[handle], action.scope == scope, action.recipient == recipient, now <= action.expires else { throw DGPluginError(code: "stale_handle", message: "native confirmation was already used or expired") }
        actions.removeValue(forKey: handle)
        guard !paidRecipient else { throw DGPluginError(code: "permission_denied", message: "plugins cannot send paid messages") }
        return action.text
    }

    public func cancel(handle: String) { lock.lock(); actions.removeValue(forKey: handle); lock.unlock() }
    public func removeAll() { lock.lock(); actions.removeAll(); lock.unlock() }
    public func removeAll(scope: String) { lock.lock(); actions = actions.filter { $0.value.scope != scope }; lock.unlock() }
}
