import Foundation
import XCTest
@testable import DGPluginNetwork

final class DGPluginNetworkAttemptsTests: XCTestCase {
    func testFallbackOrderAndSharedDeadline() {
        var attempts = DGPluginNetworkAttempts(addresses: ["2606:4700:4700::1111", "1.1.1.1", "8.8.8.8"], deadline: 10)
        let first = attempts.next(now: 1)
        XCTAssertEqual(first?.address, "2606:4700:4700::1111")
        XCTAssertEqual(first?.deadline, 3)
        let second = attempts.next(now: 3)
        XCTAssertEqual(second?.address, "1.1.1.1")
        XCTAssertEqual(second?.deadline, 5)
        let last = attempts.next(now: 5)
        XCTAssertEqual(last?.address, "8.8.8.8")
        XCTAssertEqual(last?.deadline, 10)
        XCTAssertNil(attempts.next(now: 9))
        var single = DGPluginNetworkAttempts(addresses: ["1.1.1.1"], deadline: 10)
        XCTAssertEqual(single.next(now: 1)?.deadline, 10)
        var expired = DGPluginNetworkAttempts(addresses: ["1.1.1.1"], deadline: 10)
        XCTAssertNil(expired.next(now: 10))
        XCTAssertNil(expired.next(now: 11))
    }
}
