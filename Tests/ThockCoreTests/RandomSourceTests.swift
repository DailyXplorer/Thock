import Testing
@testable import ThockCore

struct RandomSourceTests {
    @Test(arguments: [2, 3, 4, 7])
    func neverRepeatsTheVariantJustPlayed(count: Int) {
        var random = RandomSource(seed: 42)
        var previous = -1
        var seen = [Int](repeating: 0, count: count)
        for _ in 0..<10_000 {
            let pick = random.index(count: count, avoiding: previous)
            #expect(pick != previous)
            #expect((0..<count).contains(pick))
            seen[pick] += 1
            previous = pick
        }
        let share = seen.map { Double($0) / 10_000 }
        #expect(share.allSatisfy { abs($0 - 1 / Double(count)) < 0.03 })
    }

    @Test func singleVariantAlwaysPlays() {
        var random = RandomSource(seed: 1)
        #expect((0..<100).map { _ in random.index(count: 1, avoiding: 0) } == Array(repeating: 0, count: 100))
    }

    @Test func attenuationNeverExceedsTheRecordedLevel() {
        var random = RandomSource(seed: 7)
        let gains = (0..<10_000).map { _ in random.attenuation(upTo: 4) }
        let low: Float = 0.630_957
        #expect(gains.allSatisfy { $0 >= low && $0 <= 1 })
        #expect(gains.min()! < 0.64)
        #expect(gains.max()! > 0.99)
    }

    @Test func spreadCoversBothSides() {
        var random = RandomSource(seed: 9)
        let values = (0..<10_000).map { _ in random.spread(0.025) }
        #expect(values.allSatisfy { abs($0) <= 0.025 })
        #expect(values.min()! < -0.024)
        #expect(values.max()! > 0.024)
    }

    @Test func sameSeedSameSequence() {
        var first = RandomSource(seed: 0xC0FFEE)
        var second = RandomSource(seed: 0xC0FFEE)
        #expect((0..<16).map { _ in first.next() } == (0..<16).map { _ in second.next() })
    }
}
