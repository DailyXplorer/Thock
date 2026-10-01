import AppKit
import SwiftUI

final class WindowPresenter {
    enum ID {
        case onboarding
        case settings
    }

    private var windows: [ID: NSWindow] = [:]

    func show(_ id: ID, title: String, @ViewBuilder content: () -> some View) {
        let window = windows[id] ?? {
            let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            windows[id] = window
            return window
        }()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    func close(_ id: ID) {
        windows[id]?.close()
    }
}
