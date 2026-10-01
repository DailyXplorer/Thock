import Darwin

public struct RandomSource: Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func unit() -> Float {
        Float(next() >> 40) / Float(1 << 24)
    }

    public mutating func index(count: Int, avoiding previous: Int) -> Int {
        guard count > 1 else { return 0 }
        guard (0..<count).contains(previous) else { return Int(next() % UInt64(count)) }
        let pick = Int(next() % UInt64(count - 1))
        return pick >= previous ? pick + 1 : pick
    }

    public mutating func spread(_ spread: Float) -> Float {
        (unit() * 2 - 1) * spread
    }

    public mutating func attenuation(upTo decibels: Float) -> Float {
        exp2(-unit() * decibels * (log2(10) / 20))
    }
}
