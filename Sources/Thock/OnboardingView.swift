import SwiftUI

struct OnboardingView: View {
    let model: AppModel
    var state: AppModel.CaptureState?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Thock fait sonner votre clavier").font(.title2.bold())
                    Text("Un son de clavier mécanique à chaque frappe, dans toutes les apps.")
                        .foregroundStyle(.secondary)
                }
            }

            switch state ?? model.captureState {
            case .running, .benchmark:
                ready
            case .failed:
                failed
            case .needsPermission:
                permission
            }
        }
        .padding(24)
        .frame(width: 480, alignment: .leading)
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pour savoir quand une touche est enfoncée puis relâchée, Thock a besoin de la permission **Surveillance de l'entrée**.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Label("Thock ne lit pas ce que vous tapez et ne l'enregistre jamais.", systemImage: "eye.slash")
                Label("Aucun accès réseau : rien ne quitte votre Mac.", systemImage: "wifi.slash")
                Label("Pas besoin de l'Accessibilité.", systemImage: "checkmark.shield")
            }
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Cliquez sur « Ouvrir les Réglages Système ».")
                Text("2. Dans Confidentialité et sécurité > Surveillance de l'entrée, activez Thock.")
                Text("3. Revenez ici : Thock détecte l'autorisation tout seul, sans relance.")
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Ouvrir les Réglages Système") { model.requestPermission() }
                    .keyboardShortcut(.defaultAction)
                Spacer()
                ProgressView().controlSize(.small)
                Text("En attente de l'autorisation…").foregroundStyle(.secondary)
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("C'est prêt : tapez, Thock vous entend.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Thock vit dans la barre des menus. Le raccourci \(model.hotKey.displayString) l'active ou le coupe.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Fermer") { model.windows.close(.onboarding) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("La permission est accordée, mais la capture n'a pas démarré.", systemImage: "exclamationmark.triangle")
            HStack {
                Spacer()
                Button("Relancer Thock") { model.relaunch() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
