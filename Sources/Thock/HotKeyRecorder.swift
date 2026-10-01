import AppKit
import SwiftUI
import ThockCore

struct HotKeyRecorder: View {
    let model: AppModel
    @State private var monitor: Any?
    @State private var rejection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(monitor == nil ? model.hotKey.displayString : "Tapez le raccourci…") {
                    monitor == nil ? start() : stop()
                }
                .frame(minWidth: 140)
                Button("Par défaut") { model.setHotKey(.defaultToggle) }
                    .disabled(model.hotKey == .defaultToggle || monitor != nil)
            }
            if let message = rejection ?? model.hotKeyError {
                Text(message).font(.caption).foregroundStyle(.red)
            } else if monitor != nil {
                Text("Échap pour annuler.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear { stop() }
    }

    private func start() {
        rejection = nil
        model.suspendHotKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                stop()
                return nil
            }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch KeyCombo.from(keyCode: event.keyCode, modifiers: modifiers, characters: event.charactersIgnoringModifiers) {
            case .success(let combo):
                stop()
                model.setHotKey(combo)
            case .failure(.needsCommandOrControl):
                rejection = "Le raccourci doit contenir ⌘ ou ⌃."
            }
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        model.resumeHotKey()
    }
}
