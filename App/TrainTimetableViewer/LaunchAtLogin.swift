import Observation
import ServiceManagement

/// ログイン時の自動起動（`SMAppService.mainApp`）
@MainActor
@Observable
final class LaunchAtLogin {
    private(set) var status: SMAppService.Status = .notRegistered

    init() {
        refresh()
    }

    var isEnabled: Bool {
        status == .enabled
    }

    /// システム設定の「ログイン項目」で許可が必要な状態か
    var requiresApproval: Bool {
        status == .requiresApproval
    }

    /// システム設定側で変更されることがあるため、設定画面を開くたびに読み直す
    func refresh() {
        status = SMAppService.mainApp.status
    }

    func setEnabled(_ enabled: Bool) throws {
        defer { refresh() }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
