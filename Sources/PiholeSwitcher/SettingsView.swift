import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var address = ""
    @State private var password = ""
    @State private var allowSelfSigned = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchAtLoginError: String?
    @State private var hasSaved = false
    @State private var shortcutError: String?
    @AppStorage("showCountdown") private var showCountdown = true
    @AppStorage("shortcutPauseMinutes") private var shortcutPauseMinutes = 5

    var body: some View {
        Form {
            Section {
                TextField("Address", text: $address, prompt: Text("http://pi.hole"))
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                Toggle("Allow self-signed certificate", isOn: $allowSelfSigned)
                HStack {
                    result
                    Spacer()
                    Button("Connect") {
                        Task {
                            await model.saveSettings(
                                address: address,
                                password: password,
                                allowSelfSigned: allowSelfSigned
                            )
                            hasSaved = true
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy || address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Pi-hole")
            } footer: {
                Text("Requires Pi-hole v6 or later. You can use an app password, created in Pi-hole under Settings → Web Interface / API. One is required if two-factor login is on.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                ShortcutRecorder(title: "Pause blocking", combo: model.shortcuts[.pause]) {
                    setShortcut($0, for: .pause)
                }
                LabeledContent("Pause for") {
                    Stepper(
                        "\(shortcutPauseMinutes) \(shortcutPauseMinutes == 1 ? "minute" : "minutes")",
                        value: $shortcutPauseMinutes, in: 1...720
                    )
                }
                ShortcutRecorder(title: "Resume blocking", combo: model.shortcuts[.resume]) {
                    setShortcut($0, for: .resume)
                }
                if let shortcutError {
                    Text(shortcutError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Shortcuts work in any app and must include ⌘, ⌃ or ⌥.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section("General") {
                Toggle("Show time remaining in menu bar", isOn: $showCountdown)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            address = model.address
            password = model.password
            allowSelfSigned = model.allowSelfSigned
            hasSaved = false
        }
    }

    @ViewBuilder
    private var result: some View {
        if model.isBusy {
            ProgressView().controlSize(.small)
        } else if hasSaved {
            switch model.status {
            case .enabled, .disabled:
                Label {
                    Text("Connected")
                } icon: {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            case .failed(let message):
                Label {
                    Text(message).foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.footnote)
            case .notConfigured, .unknown:
                EmptyView()
            }
        }
    }

    private func setShortcut(_ combo: KeyCombo?, for action: HotKeyAction) {
        if let combo, model.shortcuts.contains(where: { $0.key != action && $0.value.keyCode == combo.keyCode && $0.value.carbonModifiers == combo.carbonModifiers }) {
            shortcutError = "\(combo.display) is already used by the other shortcut."
        } else if model.setShortcut(combo, for: action) {
            shortcutError = nil
        } else {
            shortcutError = "\(combo?.display ?? "That shortcut") is already in use by macOS or another app."
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard enabled != (SMAppService.mainApp.status == .enabled) else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
