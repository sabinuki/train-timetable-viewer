import SwiftUI

/// 「一般」タブ: 起動
struct GeneralSettingsView: View {
    let model: AppModel

    @State private var error: SettingsError?

    var body: some View {
        Form {
            Section("起動") {
                Toggle("ログイン時に起動", isOn: Binding(
                    get: { model.launchAtLogin.isEnabled || model.launchAtLogin.requiresApproval },
                    set: { setLaunchAtLogin($0) }))
                if model.launchAtLogin.requiresApproval {
                    HStack {
                        Text("システム設定の「ログイン項目」で許可してください")
                            .font(.caption)
                            .foregroundStyle(.orange)
                        Spacer()
                        Button("システム設定を開く") { model.launchAtLogin.openSystemSettings() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.launchAtLogin.refresh() }
        .settingsErrorAlert($error)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try model.launchAtLogin.setEnabled(enabled)
        } catch let failure {
            error = SettingsError(title: "ログイン時の起動を変更できません", message: failure.localizedDescription)
        }
    }
}
