import AppKit
import CoreGraphics

@MainActor
public enum Permissions {
    public static let inputMonitoringSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!

    public static var isInputMonitoringGranted: Bool {
        CGPreflightListenEventAccess()
    }

    @discardableResult
    public static func requestInputMonitoring() -> Bool {
        CGRequestListenEventAccess()
    }

    public static func openInputMonitoringSettings() {
        NSWorkspace.shared.open(inputMonitoringSettingsURL)
    }

    public static func waitForInputMonitoring(every interval: Duration = .seconds(1)) async -> Bool {
        while !Task.isCancelled {
            if isInputMonitoringGranted { return true }
            try? await Task.sleep(for: interval)
        }
        return false
    }
}
