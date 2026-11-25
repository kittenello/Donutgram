import XCTest
import DGSimpleSettings

final class MediaTransferRateTests: XCTestCase {
    func testSmallMediaGetsRateWithoutSizeThreshold() {
        var rate = DGMediaTransferRate()
        XCTAssertNil(rate.update(key: "photo", bytes: 0, timestamp: 0.0))
        XCTAssertEqual(rate.update(key: "photo", bytes: 128, timestamp: 0.25), 512)
    }

    func testStalledTransferStopsShowingPreviousSpeed() {
        var rate = DGMediaTransferRate()
        XCTAssertNil(rate.update(key: "video", bytes: 0, timestamp: 0.0))
        XCTAssertEqual(rate.update(key: "video", bytes: 1024, timestamp: 1.0), 1024)
        XCTAssertEqual(rate.update(key: "video", bytes: 1024, timestamp: 3.0), 0)
    }

    func testReusedNodeAndRestartDoNotInheritRate() {
        var rate = DGMediaTransferRate()
        XCTAssertNil(rate.update(key: "first", bytes: 0, timestamp: 0.0))
        XCTAssertEqual(rate.update(key: "first", bytes: 1000, timestamp: 1.0), 1000)
        XCTAssertNil(rate.update(key: "second", bytes: 100, timestamp: 2.0))
        XCTAssertEqual(rate.update(key: "second", bytes: 600, timestamp: 3.0), 500)
        XCTAssertNil(rate.update(key: "second", bytes: 0, timestamp: 4.0))
        rate.reset()
        XCTAssertNil(rate.update(key: "second", bytes: 500, timestamp: 5.0))
    }

    func testInvalidClockAndByteSamplesAreRejected() {
        var rate = DGMediaTransferRate()
        XCTAssertNil(rate.update(key: "file", bytes: -1, timestamp: 1.0))
        XCTAssertNil(rate.update(key: "file", bytes: 1, timestamp: .nan))
        XCTAssertNil(rate.update(key: "file", bytes: 1, timestamp: .infinity))
        XCTAssertNil(rate.update(key: "file", bytes: 1, timestamp: 2.0))
        XCTAssertNil(rate.update(key: "file", bytes: 2, timestamp: 1.0))
    }

    func testTransferredBytesClampProgressWithoutOverflow() {
        XCTAssertEqual(DGMediaTransferRate.transferredBytes(total: 1024, progress: 0.5), 512)
        XCTAssertEqual(DGMediaTransferRate.transferredBytes(total: 1024, progress: -1.0), 0)
        XCTAssertEqual(DGMediaTransferRate.transferredBytes(total: Int64.max, progress: 1.0), Int64.max)
        XCTAssertEqual(DGMediaTransferRate.transferredBytes(total: Int64.max, progress: 2.0), Int64.max)
        XCTAssertEqual(DGMediaTransferRate.transferredBytes(total: 1024, progress: .nan), 0)
    }
}
