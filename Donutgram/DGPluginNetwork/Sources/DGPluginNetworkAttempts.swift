import Foundation

/// The resolved public addresses of one request, tried in order; public only for its tests.
public struct DGPluginNetworkAttempts {
    private var addresses: [String]
    public let deadline: TimeInterval

    public init(addresses: [String], deadline: TimeInterval) {
        self.addresses = addresses
        self.deadline = deadline
    }

    public mutating func next(now: TimeInterval) -> (address: String, deadline: TimeInterval)? {
        guard now < deadline, !addresses.isEmpty else { return nil }
        let address = addresses.removeFirst()
        return (address, addresses.isEmpty ? deadline : min(deadline, now + 2))
    }
}
