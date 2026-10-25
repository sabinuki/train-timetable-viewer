import SwiftUI

/// 設定画面。駅までの所要時間と時刻表の取り込みは #13 で実装する
struct SettingsView: View {
    let model: AppModel

    var body: some View {
        Form {
            Text("設定項目は準備中です")
        }
        .formStyle(.grouped)
        .frame(width: 420)
    }
}
