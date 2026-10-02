import AppKit
import SwiftUI
import ThockCore

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("General", systemImage: "gearshape") }
            MuteSettings(model: model)
                .tabItem { Label("Mute", systemImage: "speaker.slash") }
            PackSettings(model: model)
                .tabItem { Label("Packs", systemImage: "waveform") }
            DiagnosticsSettings(model: model)
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
        }
        .padding()
        .frame(width: 520, height: 440)
    }
}

struct GeneralSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            LabeledContent("Turn Thock On or Off") {
                HotKeyRecorder(model: model)
            }
            Toggle("Include Synthetic Keystrokes", isOn: $model.includeSynthetic)
            Text("By default, Thock ignores keystrokes injected by software (text expanders, Keyboard Maestro, remote control) and only plays the physical keyboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Launch at Login", isOn: $model.launchAtLogin)
            if model.loginItemStatus == .requiresApproval {
                Label("Allow it in System Settings > General > Login Items.", systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = model.loginItemError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Sound") {
                Toggle("Spatialization", isOn: $model.spatialization)
                Toggle("Mouse Sounds", isOn: $model.mouseSounds)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshLoginItemStatus() }
    }
}

struct DiagnosticsSettings: View {
    let model: AppModel

    var body: some View {
        Form {
            DiagnosticsView(model: model)
        }
        .formStyle(.grouped)
    }
}

struct MuteSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Automatic Mute") {
                Toggle("When the microphone is in use (calls, dictation, recording)", isOn: $model.muteRules.microphoneInUse)
                Toggle("When the system sound output is muted", isOn: $model.muteRules.systemOutputMuted)
                Toggle("When an excluded app is frontmost", isOn: $model.muteRules.excludedApp)
            }
            Section("Excluded Apps") {
                if model.excludedBundleIDs.isEmpty {
                    Text("No excluded apps.").foregroundStyle(.secondary)
                }
                ForEach(model.excludedBundleIDs, id: \.self) { bundleID in
                    ExcludedAppRow(bundleID: bundleID) { model.removeExcludedApp(bundleID: bundleID) }
                }
                HStack {
                    Menu("Add Open App") {
                        ForEach(runningApps, id: \.bundleID) { app in
                            Button(app.name) { model.excludeApp(bundleID: app.bundleID) }
                        }
                    }
                    .fixedSize()
                    Button("Choose App…") { model.chooseAppToExclude() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var runningApps: [(bundleID: String, name: String)] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app in app.bundleIdentifier.map { ($0, app.localizedName ?? $0) } }
            .filter { $0.0 != Bundle.main.bundleIdentifier && !model.excludedBundleIDs.contains($0.0) }
            .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }
            .map { (bundleID: $0.0, name: $0.1) }
    }
}

private struct ExcludedAppRow: View {
    let bundleID: String
    let remove: () -> Void

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
            }
            VStack(alignment: .leading) {
                Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
                Text(bundleID).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Remove from List")
        }
    }
}

struct PackSettings: View {
    @Bindable var model: AppModel
    @State private var dropTargeted = false
    @State private var message: (text: String, isError: Bool)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(model.packs) { pack in
                HStack {
                    Image(systemName: pack.id == model.packID ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(pack.id == model.packID ? Color.accentColor : .secondary)
                    VStack(alignment: .leading) {
                        Text(pack.info.name)
                        Text("\(pack.info.author) · \(pack.info.license)\(pack.isImported ? " · imported" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if pack.isImported {
                        Button(role: .destructive) { delete(pack) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help("Delete This Imported Pack")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.packID = pack.id }
            }
            .overlay {
                if dropTargeted {
                    RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor, lineWidth: 3)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                importPack(url)
                return true
            } isTargeted: { dropTargeted = $0 }

            HStack {
                Button("Import Folder…") { choosePack() }
                Text("or drag a pack folder onto the list.").foregroundStyle(.secondary)
            }
            if let error = model.packError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let message {
                Text(message.text)
                    .font(.caption)
                    .foregroundStyle(message.isError ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Format: a folder with pack.json (name, author, license) and category_direction_variant.caf, .wav or .aiff files, for example alpha_down_1.caf, or one file per keyboard row, from alpha_down_r0.caf (function keys) to alpha_down_r4.caf (bottom row).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func choosePack() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        panel.message = "Choose a sound pack folder."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importPack(url)
    }

    private func importPack(_ url: URL) {
        Task {
            do {
                try await model.importPack(from: url)
                message = ("Pack imported and selected.", false)
            } catch {
                message = ("Couldn't import the pack: \(error.localizedDescription)", true)
            }
        }
    }

    private func delete(_ pack: PackEntry) {
        do {
            try model.deletePack(pack)
            message = ("“\(pack.info.name)” deleted.", false)
        } catch {
            message = ("Couldn't delete the pack: \(error.localizedDescription)", true)
        }
    }
}
