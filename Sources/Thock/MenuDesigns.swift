import SwiftUI
import ThockCore

/// One status line the popover can show, whatever the design.
struct MenuNotice: Identifiable {
    enum Tone {
        case info
        case warning
        case critical
    }

    struct Action {
        let title: String
        let perform: () -> Void
    }

    let id: String
    let tone: Tone
    let symbol: String
    let text: String
    var action: Action?
}

extension AppModel {
    /// The one-word state shown next to the switch; the notices carry the details.
    var stateTitle: String {
        switch captureState {
        case .needsPermission: "Needs Permission"
        case .failed: "Not Running"
        case .benchmark: "Benchmark"
        case .running:
            if muteReasons.contains(.manual) { "Off" } else if muteReasons.isEmpty { "On" } else { "Muted" }
        }
    }

    var notices: [MenuNotice] {
        var notices: [MenuNotice] = []
        switch captureState {
        case .needsPermission:
            notices.append(MenuNotice(id: "permission", tone: .warning, symbol: "hand.raised.fill",
                                      text: "Thock needs the Input Monitoring permission to hear your keyboard.",
                                      action: .init(title: "Set Up Permission…", perform: showOnboarding)))
        case .failed:
            notices.append(MenuNotice(id: "failed", tone: .critical, symbol: "exclamationmark.triangle.fill",
                                      text: "Permission is granted but capture didn't start.",
                                      action: .init(title: "Relaunch Thock", perform: relaunch)))
        case .benchmark:
            notices.append(MenuNotice(id: "benchmark", tone: .info, symbol: "gauge.with.dots.needle.67percent",
                                      text: "Synthetic typing benchmark (capture off)"))
        case .running:
            if muteReasons.contains(.manual) {
                notices.append(MenuNotice(id: "manual", tone: .info, symbol: "keyboard",
                                          text: "Press \(hotKey.displayString) to turn Thock back on."))
            }
            if muteReasons.contains(.microphoneInUse) {
                notices.append(MenuNotice(id: "microphone", tone: .info, symbol: "mic.fill", text: "Muted while the microphone is in use"))
            }
            if muteReasons.contains(.excludedApp) {
                notices.append(MenuNotice(id: "excluded", tone: .info, symbol: "app.badge.checkmark",
                                          text: "Muted while \(excludedFrontAppName ?? "an excluded app") is frontmost"))
            }
            if muteReasons.contains(.systemOutputMuted) {
                notices.append(MenuNotice(id: "output", tone: .info, symbol: "speaker.slash.fill", text: "Muted because the audio output is muted"))
            }
        }
        if secureInputActive {
            notices.append(MenuNotice(id: "secure", tone: .info, symbol: "lock.fill",
                                      text: "Secure input is on: macOS hides keystrokes from every app, so Thock stays silent."))
        }
        if let packError {
            notices.append(MenuNotice(id: "pack", tone: .warning, symbol: "exclamationmark.triangle.fill", text: packError))
        }
        if isProbe {
            notices.append(MenuNotice(id: "probe", tone: .info, symbol: "waveform.badge.magnifyingglass", text: "Probe mode on"))
        }
        return notices
    }

    var selectedPack: PackEntry? { packs.first { $0.id == packID } }
}

private extension PackEntry {
    var menuTitle: String { isImported ? "\(info.name) (imported)" : info.name }

    /// The switch family of each bundled pack, a hint for picking one by ear.
    var character: String {
        if isImported { return "Imported" }
        return switch id {
        case "mxblack", "cream": "Linear"
        case "holypanda", "mxbrown": "Tactile"
        case "mxblue", "boxnavy", "bluealps": "Clicky"
        case "topre": "Electro-capacitive"
        default: info.author
        }
    }
}

private extension MenuNotice.Tone {
    var tint: Color {
        switch self {
        case .info: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }
}

// MARK: - Shared pieces

private struct NoticeView: View {
    let notice: MenuNotice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: notice.symbol)
                .foregroundStyle(notice.tone.tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 6) {
                Text(notice.text)
                    .foregroundStyle(notice.tone == .info ? .secondary : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let action = notice.action {
                    Button(action.title, action: action.perform)
                        .controlSize(.small)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(background, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var background: AnyShapeStyle {
        notice.tone == .info ? AnyShapeStyle(.fill.quaternary) : AnyShapeStyle(notice.tone.tint.opacity(0.14))
    }
}

private struct NoticeList: View {
    let model: AppModel

    var body: some View {
        let notices = model.notices
        if !notices.isEmpty {
            VStack(spacing: 6) {
                ForEach(notices) { NoticeView(notice: $0) }
            }
        }
    }
}

private struct PackPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        Picker("Pack", selection: $model.packID) {
            ForEach(model.packs) { Text($0.menuTitle).tag($0.id) }
        }
        .labelsHidden()
        .fullWidth()
    }
}

private struct OutputPicker: View {
    @Bindable var model: AppModel

    var body: some View {
        Picker("Output", selection: $model.outputUID) {
            Text("System Default Output").tag(String?.none)
            ForEach(model.outputs) { Text($0.name).tag(String?.some($0.id)) }
            if let uid = model.outputUID, !model.outputs.contains(where: { $0.id == uid }) {
                Text("Disconnected Device (using default output)").tag(String?.some(uid))
            }
        }
        .labelsHidden()
        .fullWidth()
    }
}

private extension View {
    /// Menu pickers hug their title; only macOS 26 lets them stretch to the column width.
    @ViewBuilder
    func fullWidth() -> some View {
        if #available(macOS 26.0, *) {
            buttonSizing(.flexible).frame(maxWidth: .infinity)
        } else {
            frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct VolumeSlider: View {
    @Bindable var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill")
            Slider(value: $model.volume, in: 0...1)
            Image(systemName: "speaker.wave.3.fill")
        }
        .foregroundStyle(.secondary)
        .imageScale(.small)
    }
}

private struct FooterButton: View {
    let title: String
    let shortcut: KeyEquivalent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text("⌘\(String(shortcut.character).uppercased())").foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .keyboardShortcut(shortcut, modifiers: .command)
    }
}

private struct EnabledSwitch: View {
    @Bindable var model: AppModel

    var body: some View {
        Toggle("Enabled", isOn: $model.enabled)
            .toggleStyle(.switch)
            .labelsHidden()
            .fixedSize()
            .help("Turn Thock on or off (\(model.hotKey.displayString))")
    }
}

private func quit() {
    NSApplication.shared.terminate(nil)
}

// MARK: - A: Clean native

/// Control Center–like: a one-line header with the switch, then one aligned column of full-width controls.
struct CleanMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(model.menuBarState == .on ? Color.accentColor : Color.gray, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text("Thock").font(.headline)
                    Text(model.stateTitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                EnabledSwitch(model: model)
            }
            NoticeList(model: model)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    label("Volume")
                    VolumeSlider(model: model)
                }
                GridRow {
                    label("Sound")
                    PackPicker(model: model)
                }
                GridRow {
                    label("Output")
                    OutputPicker(model: model)
                }
                GridRow {
                    label("Mouse")
                    Toggle("Play Click Sounds", isOn: $model.mouseSounds)
                        .toggleStyle(.checkbox)
                }
            }
            .padding(12)
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                FooterButton(title: "Settings…", shortcut: ",", action: model.showSettings)
                Spacer()
                FooterButton(title: "Quit Thock", shortcut: "q", action: quit)
            }
            .font(.callout)
            .padding(.horizontal, 4)
        }
        .padding(14)
        .frame(width: 320)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }
}

// MARK: - B: Pack-first

/// The sound pack is the hero: a grid of pack cards, with volume and output in a module below.
struct PackFirstMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Thock").font(.headline)
                Text(model.stateTitle).foregroundStyle(.secondary)
                Spacer()
                EnabledSwitch(model: model)
                    .controlSize(.small)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
            }
            NoticeList(model: model)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(Array(stride(from: 0, to: model.packs.count, by: 2)), id: \.self) { start in
                    GridRow {
                        ForEach(model.packs[start..<min(start + 2, model.packs.count)]) { pack in
                            PackCard(pack: pack, isSelected: pack.id == model.packID) { model.packID = pack.id }
                        }
                    }
                }
            }
            VStack(spacing: 10) {
                VolumeSlider(model: model)
                HStack(spacing: 8) {
                    Image(systemName: "hifispeaker.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    OutputPicker(model: model)
                }
                Toggle(isOn: $model.mouseSounds) {
                    Label("Mouse Click Sounds", systemImage: "computermouse.fill")
                        .labelStyle(PaddedIconLabel())
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
            }
            .padding(12)
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack {
                FooterButton(title: "Settings…", shortcut: ",", action: model.showSettings)
                Spacer()
                FooterButton(title: "Quit Thock", shortcut: "q", action: quit)
            }
            .font(.callout)
            .padding(.horizontal, 4)
        }
        .padding(14)
        .frame(width: 340)
    }
}

private struct PaddedIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.icon.foregroundStyle(.secondary).frame(width: 16)
            configuration.title
            Spacer(minLength: 0)
        }
    }
}

private struct PackCard: View {
    let pack: PackEntry
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 1) {
                Text(pack.info.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                Text(pack.character)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(.fill.quinary),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor.opacity(0.6))
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(6)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - C: Compact

/// The smallest useful popover: switch and volume on one row, two icon-labelled pickers, and a gear menu for the rest.
struct CompactMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                EnabledSwitch(model: model)
                    .controlSize(.small)
                Slider(value: $model.volume, in: 0...1)
                Text(model.volume, format: .percent.precision(.fractionLength(0)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
                Menu {
                    Toggle("Mouse Click Sounds", isOn: $model.mouseSounds)
                    Divider()
                    Button("Settings…", action: model.showSettings)
                        .keyboardShortcut(",", modifiers: .command)
                    Button("Quit Thock", action: quit)
                        .keyboardShortcut("q", modifiers: .command)
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Settings and Quit")
            }
            row("keyboard") { PackPicker(model: model) }
            row("hifispeaker") { OutputPicker(model: model) }
            NoticeList(model: model)
        }
        .padding(12)
        .frame(width: 280)
    }

    private func row(_ symbol: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            content()
        }
    }
}
