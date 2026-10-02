import Dispatch

public final class TypingBench: @unchecked Sendable {
    public static let eventsPerSecond = 17.0

    private static let keycodes: [UInt16] = [0, 1, 2, 3, 49, 12, 13, 14, 51, 36]

    private let ring: EventRing
    private let wake: DispatchSourceUserDataAdd
    private let timer: DispatchSourceTimer
    private var sent = 0

    public init(ring: EventRing, wake: DispatchSourceUserDataAdd) {
        self.ring = ring
        self.wake = wake
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "\(AppIdentity.subsystem).bench", qos: .userInteractive))
    }

    public func start(duration: Double, completion: @escaping @Sendable () -> Void) {
        let total = Int(duration * Self.eventsPerSecond)
        timer.schedule(deadline: .now(), repeating: 1 / Self.eventsPerSecond, leeway: .milliseconds(1))
        timer.setEventHandler { [self] in
            guard sent < total else {
                timer.cancel()
                completion()
                return
            }
            let keycode = Self.keycodes[(sent / 2) % Self.keycodes.count]
            ring.push(RawInputEvent(kind: sent % 2 == 0 ? .keyDown : .keyUp, keycode: keycode, timestamp: HostClock.now))
            wake.add(data: 1)
            sent += 1
        }
        timer.activate()
    }
}
