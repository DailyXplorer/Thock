import SwiftUI
import ThockCore

struct MenuView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Thock").font(.headline)
                Spacer()
                Toggle("Activé", isOn: $model.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .help("Activer ou couper Thock (\(model.hotKey.displayString))")
            }
            status
            Divider()
            sound
            Divider()
            Toggle("Inclure les frappes synthétiques", isOn: $model.includeSynthetic)
                .help("Frappes injectées par un expanseur de texte, Keyboard Maestro ou le contrôle à distance.")
            Toggle("Lancer au démarrage", isOn: $model.launchAtLogin)
            if model.loginItemStatus == .requiresApproval {
                note("À autoriser dans Réglages Système > Général > Ouverture.", systemImage: "exclamationmark.circle")
            }
            if let error = model.loginItemError {
                note(error, systemImage: "exclamationmark.triangle")
            }
            DisclosureGroup("Diagnostics") {
                TimelineView(.periodic(from: .now, by: 0.5)) { _ in diagnostics }
            }
            .font(.callout)
            Divider()
            HStack {
                Button("Réglages…") { model.showSettings() }
                Spacer()
                Button("Quitter Thock") { NSApplication.shared.terminate(nil) }
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
                note("Actif", systemImage: "checkmark.circle")
            } else {
                ForEach(muteDescriptions, id: \.self) { note($0, systemImage: "speaker.slash") }
            }
        case .benchmark:
            note("Banc de frappe synthétique (capture coupée)", systemImage: "gauge.with.dots.needle.67percent")
        case .needsPermission:
            note("Thock attend la permission Surveillance de l'entrée.", systemImage: "hand.raised")
            Button("Configurer la permission…") { model.showOnboarding() }
        case .failed:
            note("La permission est accordée mais la capture n'a pas démarré.", systemImage: "exclamationmark.triangle")
            Button("Relancer Thock") { model.relaunch() }
        }
        if model.secureInputActive {
            note("Saisie sécurisée active : macOS masque les frappes à toutes les apps, Thock se tait.", systemImage: "lock.fill")
        }
        if model.isProbe {
            note("Mode sonde actif", systemImage: "waveform.badge.magnifyingglass")
        }
    }

    private var muteDescriptions: [String] {
        var lines: [String] = []
        let reasons = model.muteReasons
        if reasons.contains(.manual) { lines.append("Coupé (\(model.hotKey.displayString) pour réactiver)") }
        if reasons.contains(.microphoneInUse) { lines.append("En sourdine : le micro est utilisé") }
        if reasons.contains(.excludedApp) { lines.append("En sourdine : \(model.excludedFrontAppName ?? "app exclue") est au premier plan") }
        if reasons.contains(.systemOutputMuted) { lines.append("En sourdine : la sortie audio est muette") }
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
                Text(pack.isImported ? "\(pack.info.name) (importé)" : pack.info.name).tag(pack.id)
            }
        }
        if let error = model.packError {
            note(error, systemImage: "exclamationmark.triangle")
        }
        Picker("Sortie", selection: $model.outputUID) {
            Text("Sortie par défaut du système").tag(String?.none)
            ForEach(model.outputs) { output in
                Text(output.name).tag(String?.some(output.id))
            }
            if let uid = model.outputUID, !model.outputs.contains(where: { $0.id == uid }) {
                Text("Périphérique déconnecté (sortie par défaut)").tag(String?.some(uid))
            }
        }
        Toggle("Spatialisation", isOn: $model.spatialization)
        Toggle("Sons de la souris", isOn: $model.mouseSounds)
    }

    @ViewBuilder
    private var diagnostics: some View {
        let stats = model.stats
        let audio = model.audioStats
        VStack(alignment: .leading, spacing: 4) {
            Text("Pressions \(stats.downs) · Relâchements \(stats.ups) · Ignorés \(stats.filtered) · Perdus \(stats.dropped)")
            if audio.isRunning {
                Text("Audio \(audio.sampleRate / 1000, format: .number.precision(.fractionLength(1))) kHz · tampon \(audio.ioBufferFrames) · sortie \(audio.outputLatencyMs, format: .number.precision(.fractionLength(1))) ms")
            } else {
                Text("Audio arrêté")
            }
            Text("Joués \(audio.played) · En retard \(audio.stale) · Voix volées \(audio.stolen) · Départs tardifs \(audio.late) · Reconstructions \(audio.rebuilds)")
            Toggle("Mesurer la latence", isOn: $model.measuringLatency)
            if model.measuringLatency {
                if let p50 = audio.latencyP50Us, let p99 = audio.latencyP99Us {
                    Text("Latence logicielle p50 \(Int(p50)) µs · p99 \(Int(p99)) µs (\(audio.latencySamples))")
                } else {
                    Text("Latence logicielle : aucune frappe mesurée")
                }
                if audio.invalidTimestamps > 0 {
                    Text("Horodatages hors horloge hôte : \(audio.invalidTimestamps)")
                }
            }
        }
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .padding(.top, 4)
    }

    private func note(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
