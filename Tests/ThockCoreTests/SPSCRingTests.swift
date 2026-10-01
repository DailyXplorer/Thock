import Foundation
import Testing
@testable import ThockCore

private func event(_ sequence: UInt64) -> RawInputEvent {
    RawInputEvent(kind: .keyDown, keycode: UInt16(truncatingIfNeeded: sequence), flags: ~sequence, timestamp: sequence)
}

struct SPSCRingTests {
    @Test func eventFitsInOneSlot() {
        #expect(MemoryLayout<RawInputEvent>.size <= 32)
    }

    @Test func popsInPushOrderWithAllFields() {
        let ring = EventRing(capacity: 128)
        for sequence in 0..<100 as Range<UInt64> {
            #expect(ring.push(event(sequence)))
        }
        for sequence in 0..<100 as Range<UInt64> {
            #expect(ring.pop() == event(sequence))
        }
        #expect(ring.pop() == nil)
    }

    @Test func emptyRingPopsNothing() {
        let ring = EventRing(capacity: 4)
        #expect(ring.pop() == nil)
        ring.push(event(1))
        #expect(ring.pop() == event(1))
        #expect(ring.pop() == nil)
    }

    @Test func fullRingRejectsAndCountsUntilTheConsumerFreesASlot() {
        let ring = EventRing(capacity: 8)
        for sequence in 0..<8 as Range<UInt64> {
            #expect(ring.push(event(sequence)))
        }
        #expect(!ring.push(event(8)))
        #expect(!ring.push(event(9)))
        #expect(ring.droppedCount == 2)
        #expect(ring.pop() == event(0))
        #expect(ring.push(event(10)))
        let rest = (0..<8).compactMap { _ in ring.pop() }.map(\.timestamp)
        #expect(rest == [1, 2, 3, 4, 5, 6, 7, 10])
    }

    @Test func concurrentProducerAndConsumerLoseAndReorderNothing() {
        let ring = EventRing(capacity: 256)
        let total: UInt64 = 500_000
        let producer = Thread {
            var sequence: UInt64 = 0
            while sequence < total {
                if ring.push(event(sequence)) { sequence += 1 }
            }
        }
        producer.start()

        var expected: UInt64 = 0
        var mismatches = 0
        while expected < total {
            guard let popped = ring.pop() else { continue }
            if popped != event(expected) { mismatches += 1 }
            expected += 1
        }
        #expect(mismatches == 0)
        #expect(expected == total)
        #expect(ring.pop() == nil)
    }
}
