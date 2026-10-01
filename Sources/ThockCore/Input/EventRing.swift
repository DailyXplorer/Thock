internal import CRing

public final class EventRing: @unchecked Sendable {
    private let storage: UnsafeMutableRawPointer

    public init(capacity: Int = 256) {
        precondition(MemoryLayout<RawInputEvent>.size <= Int(THOCK_RING_SLOT_SIZE))
        guard let storage = thock_ring_create(capacity) else {
            preconditionFailure("EventRing capacity must be a power of two, got \(capacity)")
        }
        self.storage = storage
    }

    deinit {
        thock_ring_destroy(storage)
    }

    public var capacity: Int { thock_ring_capacity(storage) }

    public var droppedCount: UInt64 { thock_ring_dropped(storage) }

    @discardableResult
    public func push(_ event: RawInputEvent) -> Bool {
        withUnsafePointer(to: event) { thock_ring_push(storage, $0, MemoryLayout<RawInputEvent>.size) }
    }

    public func pop() -> RawInputEvent? {
        var event = RawInputEvent.reset
        let popped = withUnsafeMutablePointer(to: &event) { thock_ring_pop(storage, $0, MemoryLayout<RawInputEvent>.size) }
        return popped ? event : nil
    }
}
