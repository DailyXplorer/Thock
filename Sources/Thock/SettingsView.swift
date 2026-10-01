import AppKit
import SwiftUI
import ThockCore

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            GeneralSettings(model: model)
                .tabItem { Label("Général", systemImage: "gearshape") }
            MuteSettings(model: model)
                .tabItem { Label("Sourdine", systemImage: "speaker.slash") }
            PackSettings(model: model)
                .tabItem { Label("Packs", systemImage: "waveform") }
        }
        .padding()
        .frame(width: 520, height: 440)
    }
}

struct GeneralSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            LabeledContent("Activer ou couper Thock") {
                HotKeyRecorder(model: model)
            }
            Toggle("Inclure les frappes synthétiques", isOn: $model.includeSynthetic)
            Text("Par défaut, Thock ignore les frappes injectées par un logiciel (expanseur de texte, Keyboard Maestro, contrôle à distance) et ne joue que le clavier physique.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Lancer au démarrage", isOn: $model.launchAtLogin)
        }
        .formStyle(.grouped)
    }
}

struct MuteSettings: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Sourdine automatique") {
                Toggle("Quand le micro est utilisé (appel, dictée, enregistrement)", isOn: $model.muteRules.microphoneInUse)
                Toggle("Quand la sortie son du système est muette", isOn: $model.muteRules.systemOutputMuted)
                Toggle("Quand une app exclue est au premier plan", isOn: $model.muteRules.excludedApp)
            }
            Section("Apps exclues") {
                if model.excludedBundleIDs.isEmpty {
                    Text("Aucune app exclue.").foregroundStyle(.secondary)
                }
                ForEach(model.excludedBundleIDs, id: \.self) { bundleID in
                    ExcludedAppRow(bundleID: bundleID) { model.removeExcludedApp(bundleID: bundleID) }
                }
                HStack {
                    Menu("Ajouter une app ouverte") {
                        ForEach(runningApps, id: \.bundleID) { app in
                            Button(app.name) { model.excludeApp(bundleID: app.bundleID) }
                        }
                    }
                    .fixedSize()
                    Button("Choisir une app…") { model.chooseAppToExclude() }
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
                .help("Retirer de la liste")
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
                        Text("\(pack.info.author) · \(pack.info.license)\(pack.isImported ? " · importé" : "")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if pack.isImported {
                        Button(role: .destructive) { delete(pack) } label: { Image(systemName: "trash") }
                            .buttonStyle(.borderless)
                            .help("Supprimer ce pack importé")
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
                Button("Importer un dossier…") { choosePack() }
                Text("ou glissez un dossier de pack sur la liste.").foregroundStyle(.secondary)
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
            Text("Format : un dossier avec pack.json (name, author, license) et des fichiers catégorie_direction_variante.caf, .wav ou .aiff, par exemple alpha_down_1.caf, ou un fichier par rangée du clavier, de alpha_down_r0.caf (touches F) à alpha_down_r4.caf (rangée du bas).")
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
        panel.prompt = "Importer"
        panel.message = "Choisissez le dossier d'un pack de sons."
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        importPack(url)
    }

    private func importPack(_ url: URL) {
        Task {
            do {
                try await model.importPack(from: url)
                message = ("Pack importé et sélectionné.", false)
            } catch {
                message = ("Import impossible : \(error.localizedDescription)", true)
            }
        }
    }

    private func delete(_ pack: PackEntry) {
        do {
            try model.deletePack(pack)
            message = ("« \(pack.info.name) » supprimé.", false)
        } catch {
            message = ("Suppression impossible : \(error.localizedDescription)", true)
        }
    }
}
