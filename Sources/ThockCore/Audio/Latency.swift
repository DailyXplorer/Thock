import Darwin

public enum HostClock {
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    public static var now: UInt64 { mach_absolute_time() }

    public static func nanoseconds(_ ticks: UInt64) -> UInt64 {
        ticks / UInt64(timebase.denom) * UInt64(timebase.numer)
            + ticks % UInt64(timebase.denom) * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    public static func ticks(nanoseconds: UInt64) -> UInt64 {
        nanoseconds / UInt64(timebase.numer) * UInt64(timebase.denom)
            + nanoseconds % UInt64(timebase.numer) * UInt64(timebase.denom) / UInt64(timebase.numer)
    }
}

public struct LatencyHistogram: Sendable {
    public static let bucketWidth: UInt64 = 10_000
    public static let bucketCount = 2_000

    private var buckets = ContiguousArray<UInt32>(repeating: 0, count: bucketCount + 1)
    public private(set) var count = 0

    public init() {}

    public mutating func record(nanoseconds: UInt64) {
        buckets[Int(min(nanoseconds / Self.bucketWidth, UInt64(Self.bucketCount)))] += 1
        count += 1
    }

    public mutating func reset() {
        buckets.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        count = 0
    }

    public func percentile(_ fraction: Double) -> Double? {
        guard count > 0 else { return nil }
        let rank = max(1, Int((Double(count) * fraction).rounded(.up)))
        var seen = 0
        for (index, value) in buckets.enumerated() {
            seen += Int(value)
            if seen >= rank {
                return Double(UInt64(index + 1) * Self.bucketWidth) / 1_000
            }
        }
        return nil
    }
}
