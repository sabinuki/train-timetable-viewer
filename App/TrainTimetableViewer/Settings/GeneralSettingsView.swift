import SwiftUI
import TimetableCore

/// 「一般」タブ: 起動、ショートカット、追加の休日
struct GeneralSettingsView: View {
    let model: AppModel

    @State private var error: SettingsError?
    @State private var newHoliday = Date()

    private var viewModel: DepartureBoardViewModel { model.viewModel }

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

            Section("ショートカット") {
                LabeledContent("パネルの表示 / 非表示") {
                    HotKeyRecorder(model: model)
                }
            }

            Section {
                ForEach(viewModel.additionalHolidays.sorted(), id: \.self) { date in
                    HStack {
                        Text(Self.format(date))
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.additionalHolidays.remove(date)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help("削除")
                    }
                }
                HStack {
                    DatePicker("追加する日", selection: $newHoliday, displayedComponents: .date)
                    Button("追加") {
                        viewModel.additionalHolidays.insert(CalendarDate(newHoliday, calendar: ServiceDayResolver.japaneseCalendar))
                    }
                }
            } header: {
                Text("土休日ダイヤとして扱う日")
            } footer: {
                Text("年末年始（12/30〜1/3）など、祝日ではないが鉄道会社が土休日ダイヤで運行する日を追加します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { model.launchAtLogin.refresh() }
        .settingsErrorAlert($error)
    }

    private static func format(_ date: CalendarDate) -> String {
        let weekdays = ["日", "月", "火", "水", "木", "金", "土"]
        return "\(date.year)/\(date.month)/\(date.day)（\(weekdays[date.weekday - 1])）"
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try model.launchAtLogin.setEnabled(enabled)
        } catch let failure {
            error = SettingsError(title: "ログイン時の起動を変更できません", message: failure.localizedDescription)
        }
    }
}
