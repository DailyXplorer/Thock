import AppKit
import os
import SwiftUI

enum Snapshots {
    static func write(model: AppModel) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        render(MenuView(model: model), size: CGSize(width: 320, height: 520), to: folder.appendingPathComponent("menu.png"))
        render(OnboardingView(model: model, state: .needsPermission), size: CGSize(width: 480, height: 420), to: folder.appendingPathComponent("onboarding.png"))
        render(OnboardingView(model: model, state: .running), size: CGSize(width: 480, height: 260), to: folder.appendingPathComponent("onboarding-ready.png"))
        render(GeneralSettings(model: model), size: CGSize(width: 520, height: 400), to: folder.appendingPathComponent("settings-general.png"))
        render(MuteSettings(model: model), size: CGSize(width: 520, height: 400), to: folder.appendingPathComponent("settings-mute.png"))
        render(PackSettings(model: model).padding(), size: CGSize(width: 520, height: 400), to: folder.appendingPathComponent("settings-packs.png"))
        Logger(subsystem: "com.louis.thock", category: "snapshot").notice("Snapshots written to \(folder.path, privacy: .public)")
    }

    private static func render(_ view: some View, size: CGSize, to url: URL) {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height, alignment: .top)
            .background(Color(nsColor: .windowBackgroundColor)))
        host.frame = CGRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }
}
