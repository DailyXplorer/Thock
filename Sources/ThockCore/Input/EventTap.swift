import Carbon.HIToolbox
import CoreGraphics
import Foundation

public final class EventTap: @unchecked Sendable {
    public enum Location: Sendable {
        case session
        case hid

        var cgLocation: CGEventTapLocation {
            switch self {
            case .session: .cgSessionEventTap
            case .hid: .cghidEventTap
            }
        }
    }

    private static let eventMask: CGEventMask = {
        let types: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp]
        return types.reduce(0) { $0 | (1 << $1.rawValue) }
    }()

    private let context: TapContext
    private let location: Location
    private let watchdogInterval: CFTimeInterval
    private var runLoop: CFRunLoop?

    public init(ring: EventRing, wake: DispatchSourceUserDataAdd, location: Location = .session,
                watchdogInterval: TimeInterval = 3, onPermissionLost: @escaping @Sendable () -> Void) {
        context = TapContext(ring: ring, wake: wake, onPermissionLost: onPermissionLost)
        self.location = location
        self.watchdogInterval = watchdogInterval
    }

    deinit {
        stop()
    }

    public var isRunning: Bool { runLoop != nil }

    public func start() -> Bool {
        guard runLoop == nil else { return true }
        let handshake = Handshake()
        let thread = Thread { [context, location, watchdogInterval] in
            Self.run(context: context, location: location, watchdogInterval: watchdogInterval, handshake: handshake)
        }
        thread.name = "\(AppIdentity.subsystem).event-tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        handshake.done.wait()
        runLoop = handshake.runLoop
        return runLoop != nil
    }

    public func stop() {
        guard let runLoop else { return }
        CFRunLoopStop(runLoop)
        self.runLoop = nil
    }

    private static func run(context: TapContext, location: Location, watchdogInterval: CFTimeInterval, handshake: Handshake) {
        guard let port = CGEvent.tapCreate(tap: location.cgLocation, place: .headInsertEventTap, options: .listenOnly,
                                           eventsOfInterest: eventMask, callback: tapCallback,
                                           userInfo: Unmanaged.passUnretained(context).toOpaque()) else {
            handshake.done.signal()
            return
        }
        context.port = port
        context.permissionLostReported = false
        let runLoop = CFRunLoopGetCurrent()
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(runLoop, source, .commonModes)
        let watchdog = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + watchdogInterval,
                                                       watchdogInterval, 0, 0) { _ in context.watchdog() }
        CFRunLoopTimerSetTolerance(watchdog, watchdogInterval / 3)
        CFRunLoopAddTimer(runLoop, watchdog, .commonModes)

        handshake.runLoop = runLoop
        handshake.done.signal()
        CFRunLoopRun()

        CFRunLoopTimerInvalidate(watchdog)
        CGEvent.tapEnable(tap: port, enable: false)
        CFRunLoopRemoveSource(runLoop, source, .commonModes)
        CFMachPortInvalidate(port)
        context.port = nil
    }
}

private final class Handshake: @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    var runLoop: CFRunLoop?
}

private final class TapContext: @unchecked Sendable {
    let ring: EventRing
    let wake: DispatchSourceUserDataAdd
    let onPermissionLost: @Sendable () -> Void
    var port: CFMachPort?
    var permissionLostReported = false
    var lastKeyboardType: Int64 = -1
    var lastKeyboardIsISO = false

    init(ring: EventRing, wake: DispatchSourceUserDataAdd, onPermissionLost: @escaping @Sendable () -> Void) {
        self.ring = ring
        self.wake = wake
        self.onPermissionLost = onPermissionLost
    }

    func push(_ event: RawInputEvent) {
        ring.push(event)
        wake.add(data: 1)
    }

    func reenable() {
        guard let port else { return }
        CGEvent.tapEnable(tap: port, enable: true)
        push(.reset)
    }

    func watchdog() {
        guard let port else { return }
        if !CGPreflightListenEventAccess() {
            if !permissionLostReported {
                permissionLostReported = true
                onPermissionLost()
            }
        } else if !CGEvent.tapIsEnabled(tap: port) {
            reenable()
        }
    }

    func isISO(_ keyboardType: Int64) -> Bool {
        if keyboardType != lastKeyboardType {
            lastKeyboardType = keyboardType
            lastKeyboardIsISO = KBGetLayoutType(Int16(truncatingIfNeeded: keyboardType)) == PhysicalKeyboardLayoutType(kKeyboardISO)
        }
        return lastKeyboardIsISO
    }

    func handle(_ type: CGEventType, _ event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            reenable()
        default:
            guard let kind = InputKind(type) else { return }
            let keycode: UInt16 = switch type {
            case .leftMouseDown, .leftMouseUp: KeyMap.leftMouseButton
            case .rightMouseDown, .rightMouseUp: KeyMap.rightMouseButton
            default: KeyMap.positionalKeycode(UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode)),
                                              isISO: isISO(event.getIntegerValueField(.keyboardEventKeyboardType)))
            }
            push(RawInputEvent(kind: kind,
                               keycode: keycode,
                               flags: event.flags.rawValue,
                               isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
                               sourceStateID: event.getIntegerValueField(.eventSourceStateID),
                               sourcePID: Int32(truncatingIfNeeded: event.getIntegerValueField(.eventSourceUnixProcessID)),
                               timestamp: event.timestamp))
        }
    }
}

private func tapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                         userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if let userInfo {
        Unmanaged<TapContext>.fromOpaque(userInfo).takeUnretainedValue().handle(type, event)
    }
    return Unmanaged.passUnretained(event)
}
