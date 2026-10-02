import Dispatch
import os

public struct InputStats: Sendable, Equatable {
    public var downs: UInt64 = 0
    public var ups: UInt64 = 0
    public var filtered: UInt64 = 0
    public var dropped: UInt64 = 0
}

public final class InputPipeline: @unchecked Sendable {
    public let ring: EventRing
    public let wakeSource: DispatchSourceUserDataAdd

    private let queue: DispatchQueue
    private let sink: @Sendable (SoundTrigger, UInt64) -> Void
    private let probeLogger: Logger?
    private let counters = OSAllocatedUnfairLock(initialState: InputStats())

    private var machine = KeyStateMachine()
    private var filter: SourceFilter

    public init(queue: DispatchQueue, ring: EventRing = EventRing(), filter: SourceFilter = SourceFilter(),
                probe: Bool = false, sink: @escaping @Sendable (SoundTrigger, UInt64) -> Void) {
        self.queue = queue
        self.ring = ring
        self.filter = filter
        self.sink = sink
        probeLogger = probe ? Logger(subsystem: AppIdentity.subsystem, category: "probe") : nil
        wakeSource = DispatchSource.makeUserDataAddSource(queue: queue)
        _ = KeyMap.entry(for: 0)
        wakeSource.setEventHandler { [weak self] in self?.drain() }
        wakeSource.activate()
    }

    deinit {
        wakeSource.cancel()
    }

    public var stats: InputStats {
        var stats = counters.withLock { $0 }
        stats.dropped = ring.droppedCount
        return stats
    }

    public func setIncludeSynthetic(_ include: Bool) {
        queue.async { self.filter.includeSynthetic = include }
    }

    public func reset() {
        queue.async { self.machine.reset() }
    }

    func flush() {
        queue.sync { drain() }
    }

    func drain() {
        while let event = ring.pop() {
            let accepted = filter.accepts(event)
            probeLogger?.notice("type=\(event.kind.probeName, privacy: .public) stateID=\(event.sourceStateID, privacy: .public) pid=\(event.sourcePID, privacy: .public) accepted=\(accepted, privacy: .public)")
            guard accepted else {
                counters.withLock { $0.filtered += 1 }
                continue
            }
            for trigger in machine.reduce(event) {
                counters.withLock {
                    if trigger.direction == .down { $0.downs += 1 } else { $0.ups += 1 }
                }
                sink(trigger, event.timestamp)
            }
        }
    }
}

private extension InputKind {
    var probeName: String {
        switch self {
        case .keyDown: "keyDown"
        case .keyUp: "keyUp"
        case .flagsChanged: "flagsChanged"
        case .mouseDown: "mouseDown"
        case .mouseUp: "mouseUp"
        case .reset: "reset"
        }
    }
}
