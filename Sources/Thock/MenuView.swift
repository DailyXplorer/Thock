import SwiftUI
import ThockCore

/// Popover design proposals under review. The hidden `menuDesign` default picks one
/// (`defaults write io.github.dailyxplorer.thock menuDesign A`, or B or C); anything else keeps the current design.
enum MenuDesign: String, CaseIterable {
    case current
    case clean = "A"
    case packFirst = "B"
    case compact = "C"

    static var selected: MenuDesign {
        UserDefaults.standard.string(forKey: "menuDesign").flatMap(MenuDesign.init(rawValue:)) ?? .current
    }
}

struct MenuView: View {
    let model: AppModel
    var design = MenuDesign.selected

    var body: some View {
        switch design {
        case .current: CurrentMenu(model: model)
        case .clean: CleanMenu(model: model)
        case .packFirst: PackFirstMenu(model: model)
        case .compact: CompactMenu(model: model)
        }
    }
}

struct CurrentMenu: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Thock").font(.headline)
                Spacer()
                Toggle("Enabled", isOn: $model.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Turn Thock on or off (\(model.hotKey.displayString))")
            }
            status
            Divider()
            sound
            Divider()
            Toggle("Include Synthetic Keystrokes", isOn: $model.includeSynthetic)
                .help("Keystrokes injected by a text expander, Keyboard Maestro or remote control.")
            Toggle("Launch at Login", isOn: $model.launchAtLogin)
            if model.loginItemStatus == .requiresApproval {
                note("Allow it in System Settings > General > Login Items.", systemImage: "exclamationmark.circle")
            }
            if let error = model.loginItemError {
                note(error, systemImage: "exclamationmark.triangle")
            }
            DisclosureGroup("Diagnostics") {
                DiagnosticsView(model: model)
                    .padding(.top, 4)
            }
            .font(.callout)
            Divider()
            HStack {
                Button("Settings…") { model.showSettings() }
                Spacer()
                Button("Quit Thock") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding()
        .frame(width: 320, alignment: .leading)
        .onAppear { model.refreshLoginItemStatus() }
    }

    @ViewBuilder
    private var status: some View {
        switch model.captureState {
        case .running:
            if model.muteReasons.isEmpty {
                note("Active", systemImage: "checkmark.circle")
            } else {
                ForEach(muteDescriptions, id: \.self) { note($0, systemImage: "speaker.slash") }
            }
        case .benchmark:
            note("Synthetic typing benchmark (capture off)", systemImage: "gauge.with.dots.needle.67percent")
        case .needsPermission:
            note("Thock is waiting for the Input Monitoring permission.", systemImage: "hand.raised")
            Button("Set Up Permission…") { model.showOnboarding() }
        case .failed:
            note("Permission is granted but capture didn't start.", systemImage: "exclamationmark.triangle")
            Button("Relaunch Thock") { model.relaunch() }
        }
        if model.secureInputActive {
            note("Secure input is on: macOS hides keystrokes from every app, so Thock stays silent.", systemImage: "lock.fill")
        }
        if model.isProbe {
            note("Probe mode on", systemImage: "waveform.badge.magnifyingglass")
        }
    }

    private var muteDescriptions: [String] {
        var lines: [String] = []
        let reasons = model.muteReasons
        if reasons.contains(.manual) { lines.append("Off (\(model.hotKey.displayString) to turn back on)") }
        if reasons.contains(.microphoneInUse) { lines.append("Muted: the microphone is in use") }
        if reasons.contains(.excludedApp) { lines.append("Muted: \(model.excludedFrontAppName ?? "an excluded app") is frontmost") }
        if reasons.contains(.systemOutputMuted) { lines.append("Muted: the audio output is muted") }
        return lines
    }

    @ViewBuilder
    private var sound: some View {
        HStack {
            Image(systemName: "speaker.fill")
            Slider(value: $model.volume, in: 0...1)
            Image(systemName: "speaker.wave.3.fill")
        }
        .foregroundStyle(.secondary)
        Picker("Pack", selection: $model.packID) {
            ForEach(model.packs) { pack in
                Text(pack.isImported ? "\(pack.info.name) (imported)" : pack.info.name).tag(pack.id)
            }
        }
        if let error = model.packError {
            note(error, systemImage: "exclamationmark.triangle")
        }
        Picker("Output", selection: $model.outputUID) {
            Text("System Default Output").tag(String?.none)
            ForEach(model.outputs) { output in
                Text(output.name).tag(String?.some(output.id))
            }
            if let uid = model.outputUID, !model.outputs.contains(where: { $0.id == uid }) {
                Text("Disconnected Device (using default output)").tag(String?.some(uid))
            }
        }
        Toggle("Spatialization", isOn: $model.spatialization)
        Toggle("Mouse Sounds", isOn: $model.mouseSounds)
    }

    private func note(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
