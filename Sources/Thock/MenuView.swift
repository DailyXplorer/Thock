import SwiftUI
import ThockCore

/// One status line the popover can show under its header.
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
}

/// Control Center–like: a one-line header with the switch, then one aligned column of full-width controls.
/// Everything set once and rarely changed lives in Settings.
struct MenuView: View {
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
                Toggle("Enabled", isOn: $model.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .fixedSize()
                    .help("Turn Thock on or off (\(model.hotKey.displayString))")
            }
            let notices = model.notices
            if !notices.isEmpty {
                VStack(spacing: 6) {
                    ForEach(notices) { NoticeView(notice: $0) }
                }
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    label("Volume")
                    HStack(spacing: 8) {
                        Image(systemName: "speaker.fill")
                        Slider(value: $model.volume, in: 0...1)
                        Image(systemName: "speaker.wave.3.fill")
                    }
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                }
                GridRow {
                    label("Sound")
                    Picker("Pack", selection: $model.packID) {
                        ForEach(model.packs) { pack in
                            Text(pack.isImported ? "\(pack.info.name) (imported)" : pack.info.name).tag(pack.id)
                        }
                    }
                    .labelsHidden()
                    .fullWidth()
                }
                GridRow {
                    label("Output")
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
                FooterButton(title: "Quit Thock", shortcut: "q") { NSApplication.shared.terminate(nil) }
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

private extension MenuNotice.Tone {
    var tint: Color {
        switch self {
        case .info: .secondary
        case .warning: .orange
        case .critical: .red
        }
    }
}

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

struct DiagnosticsView: View {
    @Bindable var model: AppModel

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in content }
    }

    @ViewBuilder
    private var content: some View {
        let stats = model.stats
        let audio = model.audioStats
        VStack(alignment: .leading, spacing: 4) {
            Text("Presses \(stats.downs) · Releases \(stats.ups) · Ignored \(stats.filtered) · Dropped \(stats.dropped)")
            if audio.isRunning {
                Text("Audio \(audio.sampleRate / 1000, format: .number.precision(.fractionLength(1))) kHz · buffer \(audio.ioBufferFrames) · output \(audio.outputLatencyMs, format: .number.precision(.fractionLength(1))) ms")
            } else {
                Text("Audio stopped")
            }
            Text("Played \(audio.played) · Stale \(audio.stale) · Stolen voices \(audio.stolen) · Late starts \(audio.late) · Rebuilds \(audio.rebuilds)")
            Toggle("Measure Latency", isOn: $model.measuringLatency)
            if model.measuringLatency {
                if let p50 = audio.latencyP50Us, let p99 = audio.latencyP99Us {
                    Text("Software latency p50 \(Int(p50)) µs · p99 \(Int(p99)) µs (\(audio.latencySamples))")
                } else {
                    Text("Software latency: no keystrokes measured yet")
                }
                if audio.invalidTimestamps > 0 {
                    Text("Timestamps off the host clock: \(audio.invalidTimestamps)")
                }
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
    }
}
