import SwiftUI
import TimetableCore

/// 「パネル」タブ: フローティングパネルの見た目と挙動
struct PanelSettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model

        Form {
            Section {
                LabeledContent("不透明度") {
                    HStack {
                        Slider(value: $model.panelOpacity, in: AppSettings.panelOpacityRange)
                        Text(model.panelOpacity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("クリックを透過する", isOn: $model.isClickThrough)
            } footer: {
                Text("透過中はパネルの上から下のウィンドウを操作できます。解除はメニューバーの「パネルのクリックを透過」から行えます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
