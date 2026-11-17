import Foundation

public struct DGMediaTransferRate {
    private var key: String?
    private var previousTime: Double = 0.0
    private var previousBytes: Int64 = 0
    private var lastProgressTime: Double = 0.0
    private var rate: Double?

    public init() {
    }

    public static func transferredBytes(total: Int64, progress: Float) -> Int64 {
        guard total > 0, progress.isFinite else { return 0 }
        let value = Double(total) * Double(min(1.0, max(0.0, progress)))
        return value >= Double(total) ? total : Int64(value)
    }

    public mutating func reset() {
        self = DGMediaTransferRate()
    }

    public mutating func update(key: String, bytes: Int64, timestamp: Double) -> Int64? {
        guard bytes >= 0, timestamp.isFinite else {
            self.reset()
            return nil
        }
        if self.key != key || bytes < self.previousBytes || timestamp < self.previousTime {
            self.key = key
            self.previousTime = timestamp
            self.lastProgressTime = timestamp
            self.previousBytes = bytes
            self.rate = nil
            return nil
        }
        let elapsed = timestamp - self.previousTime
        if elapsed >= 0.1 && bytes > self.previousBytes {
            let sample = Double(bytes - self.previousBytes) / elapsed
            self.rate = self.rate.map { $0 * 0.4 + sample * 0.6 } ?? sample
            self.previousTime = timestamp
            self.previousBytes = bytes
            self.lastProgressTime = timestamp
        }
        if timestamp - self.lastProgressTime >= 2.0 {
            return 0
        }
        return self.rate.map { Int64(min(Double(Int64.max / 2), max(0.0, $0))) }
    }
}
