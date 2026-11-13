import Foundation

struct DGPluginNetworkAttempts {
    private var addresses: [String]
    let deadline: TimeInterval

    init(addresses: [String], deadline: TimeInterval) {
        self.addresses = addresses
        self.deadline = deadline
    }

    mutating func next(now: TimeInterval) -> (address: String, deadline: TimeInterval)? {
        guard now < deadline, !addresses.isEmpty else { return nil }
        let address = addresses.removeFirst()
        return (address, addresses.isEmpty ? deadline : min(deadline, now + 2))
    }
}
