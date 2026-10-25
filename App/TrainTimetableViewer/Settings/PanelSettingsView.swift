import SwiftUI
import TimetableCore

/// 「表示」タブ: フローティングパネルとメニューバーの表示
struct PanelSettingsView: View {
    let model: AppModel

    var body: some View {
        @Bindable var model = model
        @Bindable var viewModel = model.viewModel

        Form {
            Section {
                Stepper(value: $viewModel.displayCount, in: AppSettings.displayCountRange) {
                    LabeledContent("表示する本数") {
                        Text("\(viewModel.displayCount) 本")
                    }
                }
                LabeledContent("不透明度") {
                    HStack {
                        Slider(value: $model.panelOpacity, in: AppSettings.panelOpacityRange)
                        Text(model.panelOpacity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("クリックを透過する", isOn: $model.isClickThrough)
            } header: {
                Text("パネル")
            } footer: {
                Text("透過中はパネルの上から下のウィンドウを操作できます。解除はメニューバーの「パネルのクリックを透過」から行えます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("メニューバー") {
                Picker("表示形式", selection: $viewModel.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { style in
                        Text(style.displayName).tag(style)
                    }
                }
            }

            Section {
                Toggle("残り時間を秒単位で表示する", isOn: $model.showsSeconds)
            } footer: {
                Text("オンにすると 1 秒ごとに表示を更新します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
