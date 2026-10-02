import AppKit
import SwiftUI
import ThockCore

// Renders the popover, the menu bar icon states and the Settings tabs to PNG without launching Thock.
// usage: ThockSnapshots <packs-folder>; PNGs go to $THOCK_SNAPSHOT_DIR or /tmp/thock-shots.

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: ThockSnapshots <packs-folder>\n".utf8))
    exit(2)
}
NSApplication.shared.setActivationPolicy(.prohibited)

let folder = URL(fileURLWithPath: ProcessInfo.processInfo.environment["THOCK_SNAPSHOT_DIR"] ?? "/tmp/thock-shots", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

// PackLibrary skips hidden folders, and some checkouts (iCloud-synced worktrees) carry the hidden flag on every pack
// folder, so read the packs from a copy with the flag cleared.
let scratch = FileManager.default.temporaryDirectory.appendingPathComponent("thock-snapshot-packs", isDirectory: true)
try? FileManager.default.removeItem(at: scratch)
try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
let packsCopy = scratch.appendingPathComponent("Packs", isDirectory: true)
try FileManager.default.copyItem(at: URL(fileURLWithPath: arguments[1], isDirectory: true).absoluteURL, to: packsCopy)
for var folder in try FileManager.default.contentsOfDirectory(at: packsCopy, includingPropertiesForKeys: nil) {
    var visible = URLResourceValues()
    visible.isHidden = false
    try folder.setResourceValues(visible)
}
let library = PackLibrary(bundledRoot: packsCopy, importedRoot: scratch.appendingPathComponent("Imported", isDirectory: true))
let normal = SnapshotState(packs: library.all(), packID: "mxblack",
                           outputs: [OutputDevice(id: "airpods", name: "AirPods Pro")])
var needsPermission = normal
needsPermission.captureState = .needsPermission
var muted = normal
muted.muteReasons = [.microphoneInUse]
muted.secureInputActive = true

enum Appearance: String, CaseIterable {
    case light
    case dark

    var name: NSAppearance.Name { self == .light ? .aqua : .darkAqua }
}

func writePNG(_ view: some View, width: CGFloat, appearance: Appearance, to name: String) {
    let host = NSHostingView(rootView: view.frame(width: width))
    host.appearance = NSAppearance(named: appearance.name)
    let size = CGSize(width: width, height: host.fittingSize.height)
    let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = host.appearance
    host.frame = CGRect(origin: .zero, size: size)
    window.contentView = host
    window.orderFrontRegardless()
    host.layoutSubtreeIfNeeded()
    RunLoop.current.run(until: Date().addingTimeInterval(1))
    let scale: CGFloat = 2
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
    bitmap.size = size
    host.cacheDisplay(in: host.bounds, to: bitmap)
    let url = folder.appendingPathComponent(name)
    try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    window.close()
    print(url.path)
}

/// A popover-like frame: real popovers are a translucent material over the desktop, approximated here by a solid fill over a soft gradient.
/// The offscreen window is never key, so switches draw their inactive gray track instead of the accent color.
struct PopoverStage<Content: View>: View {
    let appearance: Appearance
    @ViewBuilder let content: Content

    var body: some View {
        let dark = appearance == .dark
        content
            .background(dark ? Color(white: 0.16).opacity(0.97) : Color(white: 0.97).opacity(0.97),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)))
            .shadow(color: .black.opacity(dark ? 0.5 : 0.18), radius: 20, y: 8)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LinearGradient(colors: dark ? [Color(red: 0.10, green: 0.12, blue: 0.20), Color(red: 0.22, green: 0.16, blue: 0.28)]
                                                    : [Color(red: 0.70, green: 0.80, blue: 0.92), Color(red: 0.90, green: 0.82, blue: 0.86)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

func shoot(_ state: SnapshotState, _ appearance: Appearance, variant: String = "") {
    writePNG(PopoverStage(appearance: appearance) { MenuView(model: AppModel(snapshot: state)) },
             width: 320 + 64, appearance: appearance, to: "menu-\(variant)\(appearance.rawValue).png")
}

for appearance in Appearance.allCases {
    shoot(normal, appearance)
}
shoot(needsPermission, .light, variant: "warning-")
shoot(muted, .light, variant: "muted-")
let settingsModel = AppModel(snapshot: normal)
writePNG(GeneralSettings(model: settingsModel).frame(height: 400).background(Color(nsColor: .windowBackgroundColor)),
         width: 520, appearance: .light, to: "settings-general.png")
writePNG(DiagnosticsSettings(model: settingsModel).frame(height: 300).background(Color(nsColor: .windowBackgroundColor)),
         width: 520, appearance: .light, to: "settings-diagnostics.png")

struct IconSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            strip(dark: false)
            strip(dark: true)
        }
        .padding(20)
        .background(Color(white: 0.93))
    }

    private func strip(dark: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(MenuBarIcon.State.allCases, id: \.self) { state in
                HStack(spacing: 6) {
                    Image(nsImage: MenuBarIcon.image(state))
                        .renderingMode(.template)
                    Text(caption(state)).font(.system(size: 11))
                        .opacity(0.6)
                }
                .frame(width: 150, alignment: .leading)
            }
        }
        .foregroundStyle(dark ? Color.white : Color.black)
        .padding(.horizontal, 12)
        .frame(height: 24)
        .background(dark ? Color(white: 0.12) : Color(white: 0.98).opacity(0.9))
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    private func caption(_ state: MenuBarIcon.State) -> String {
        switch state {
        case .on: "On"
        case .off: "Off"
        case .muted: "Auto-muted"
        case .attention: "Needs permission"
        }
    }
}

writePNG(IconSheet(), width: 664, appearance: .light, to: "icons.png")
