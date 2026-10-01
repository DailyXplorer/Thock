import AppKit

@MainActor
public final class SystemEvents {
    public enum Event: Sendable, CaseIterable {
        case willSleep
        case didWake
        case screenLocked
        case screenUnlocked
        case sessionResignedActive
        case sessionBecameActive
    }

    private let handler: @MainActor (Event) -> Void
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    public init(handler: @escaping @MainActor (Event) -> Void) {
        self.handler = handler
    }

    public func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observe(workspace, NSWorkspace.willSleepNotification, .willSleep)
        observe(workspace, NSWorkspace.didWakeNotification, .didWake)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, .sessionResignedActive)
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification, .sessionBecameActive)
        observe(distributed, Notification.Name("com.apple.screenIsLocked"), .screenLocked)
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked"), .screenUnlocked)
    }

    public func stop() {
        for (center, token) in observers {
            center.removeObserver(token)
        }
        observers.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ event: Event) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handler(event) }
        }
        observers.append((center, token))
    }
}
