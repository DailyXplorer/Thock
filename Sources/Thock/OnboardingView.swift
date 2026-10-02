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
                    Text("Hear your keyboard with Thock").font(.title2.bold())
                    Text("A mechanical keyboard sound on every keystroke, in every app.")
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
            Text("To know when a key goes down and comes back up, Thock needs the **Input Monitoring** permission.")
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Label("Thock never reads or records what you type.", systemImage: "eye.slash")
                Label("No network access: nothing leaves your Mac.", systemImage: "wifi.slash")
                Label("No Accessibility access needed.", systemImage: "checkmark.shield")
            }
            .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Click “Open System Settings”.")
                Text("2. In Privacy & Security > Input Monitoring, turn on Thock.")
                Text("3. Come back here: Thock notices the permission by itself, no relaunch needed.")
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Open System Settings") { model.requestPermission() }
                    .keyboardShortcut(.defaultAction)
                Spacer()
                ProgressView().controlSize(.small)
                Text("Waiting for permission…").foregroundStyle(.secondary)
            }
        }
    }

    private var ready: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("All set: start typing and Thock will play along.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text("Thock lives in the menu bar. Press \(model.hotKey.displayString) to turn it on or off.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Close") { model.windows.close(.onboarding) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Permission is granted, but capture didn't start.", systemImage: "exclamationmark.triangle")
            HStack {
                Spacer()
                Button("Relaunch Thock") { model.relaunch() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
