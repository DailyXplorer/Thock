import Dispatch
import os
import Testing
@testable import ThockCore

private func key(_ kind: InputKind, stateID: Int64, keycode: UInt16 = 0) -> RawInputEvent {
    RawInputEvent(kind: kind, keycode: keycode, sourceStateID: stateID, sourcePID: stateID == 1 ? 0 : 4242)
}

struct SourceFilterTests {
    @Test func defaultAcceptsHardwareOnly() {
        let filter = SourceFilter()
        #expect(filter.accepts(key(.keyDown, stateID: 1)))
        #expect(!filter.accepts(key(.keyDown, stateID: 0)))
        #expect(!filter.accepts(key(.keyDown, stateID: -1)))
        #expect(!filter.accepts(key(.keyDown, stateID: 7)))
    }

    @Test func includeOptionAcceptsSyntheticInput() {
        let filter = SourceFilter(includeSynthetic: true)
        #expect(filter.accepts(key(.keyDown, stateID: 0)))
        #expect(filter.accepts(key(.keyUp, stateID: -1)))
    }

    @Test func resetIsNeverFiltered() {
        #expect(SourceFilter().accepts(.reset))
    }

    @Test func pipelineDropsSyntheticKeystrokesAndCountsThem() {
        let played = OSAllocatedUnfairLock(initialState: [Direction]())
        let pipeline = InputPipeline(queue: DispatchQueue(label: "test.pipeline")) { trigger, _ in
            played.withLock { $0.append(trigger.direction) }
        }
        for event in [key(.keyDown, stateID: 1), key(.keyDown, stateID: 0, keycode: 1), key(.keyUp, stateID: 0, keycode: 1), key(.keyUp, stateID: 1)] {
            pipeline.ring.push(event)
        }
        pipeline.flush()
        #expect(played.withLock { $0 } == [.down, .up])
        #expect(pipeline.stats == InputStats(downs: 1, ups: 1, filtered: 2, dropped: 0))
    }

    @Test func pipelinePlaysSyntheticKeystrokesOnceIncluded() {
        let played = OSAllocatedUnfairLock(initialState: 0)
        let pipeline = InputPipeline(queue: DispatchQueue(label: "test.pipeline")) { _, _ in played.withLock { $0 += 1 } }
        pipeline.setIncludeSynthetic(true)
        pipeline.ring.push(key(.keyDown, stateID: 0))
        pipeline.ring.push(key(.keyUp, stateID: 0))
        pipeline.flush()
        #expect(played.withLock { $0 } == 2)
    }

    @Test func pipelineResetForgetsHeldKeys() {
        let played = OSAllocatedUnfairLock(initialState: [Direction]())
        let pipeline = InputPipeline(queue: DispatchQueue(label: "test.pipeline")) { trigger, _ in
            played.withLock { $0.append(trigger.direction) }
        }
        pipeline.ring.push(key(.keyDown, stateID: 1))
        pipeline.flush()
        pipeline.reset()
        pipeline.ring.push(key(.keyUp, stateID: 1))
        pipeline.flush()
        #expect(played.withLock { $0 } == [.down])
    }
}
