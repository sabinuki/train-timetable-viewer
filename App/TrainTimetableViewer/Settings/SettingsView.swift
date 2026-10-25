import SwiftUI
import TimetableCore
import UniformTypeIdentifiers

/// 設定画面（設計書 §6.3 のうち MVP に必要な項目）。そのほかの項目は #20 で追加する
struct SettingsView: View {
    let model: AppModel

    @State private var isImporting = false
    @State private var errorTitle = ""
    @State private var errorMessage: String?
    @State private var importedMessage: String?

    var body: some View {
        @Bindable var viewModel = model.viewModel

        Form {
            Section("駅までの所要時間") {
                Stepper(value: $viewModel.minutesToStation, in: AppSettings.minutesToStationRange) {
                    HStack {
                        TextField(
                            "所要時間", value: $viewModel.minutesToStation, format: .number)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 48)
                        Text("分")
                    }
                }
                Text("発車時刻からこの時間を引いた時刻を「出発すべき時刻」として表示します")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("時刻表") {
                if model.storedTimetables.isEmpty {
                    Text("時刻表が取り込まれていません")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.storedTimetables, id: \.self) { timetable in
                    TimetableRow(
                        timetable: timetable,
                        isSelected: timetable.routeKey == viewModel.selectedRouteKey,
                        onDelete: { delete(timetable) })
                }
                ForEach(model.loadFailures, id: \.self) { failure in
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                HStack {
                    Button("時刻表 JSON を取り込む…") { isImporting = true }
                    if let sample = model.sampleTimetableURL {
                        Button("サンプルを取り込む") { importTimetable(from: sample) }
                    }
                }
                if let importedMessage {
                    Text(importedMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("時刻表 JSON の作り方はリポジトリの scripts/README.md を参照してください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("パネル") {
                LabeledContent("不透明度") {
                    HStack {
                        Slider(value: Bindable(model).panelOpacity, in: AppSettings.panelOpacityRange)
                        Text(model.panelOpacity, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                Toggle("クリックを透過する", isOn: Bindable(model).isClickThrough)
                Text("透過中はパネルの上から下のウィンドウを操作できます。解除はメニューバーの「パネルのクリックを透過」から行えます")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
        .onAppear { model.launchAtLogin.refresh() }
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importTimetable(from: url)
            case .failure(let error):
                errorTitle = "時刻表を取り込めません"
                errorMessage = error.localizedDescription
            }
        }
        .alert(
            errorTitle,
            isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
            presenting: errorMessage
        ) { _ in
            Button("OK") { errorMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    private func importTimetable(from url: URL) {
        Task {
            do {
                let timetable = try await model.importTimetable(from: url)
                importedMessage = "\(timetable.station.name) \(timetable.line.name) \(timetable.direction.name)（\(timetable.validFrom.description) から）を取り込みました"
            } catch {
                errorTitle = "時刻表を取り込めません"
                errorMessage = error.localizedDescription
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try model.launchAtLogin.setEnabled(enabled)
        } catch {
            errorTitle = "ログイン時の起動を変更できません"
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ timetable: Timetable) {
        do {
            try model.deleteTimetable(timetable)
            importedMessage = nil
        } catch {
            errorTitle = "時刻表を削除できません"
            errorMessage = error.localizedDescription
        }
    }
}

private struct TimetableRow: View {
    let timetable: Timetable
    let isSelected: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .help(isSelected ? "表示中" : "")
            VStack(alignment: .leading, spacing: 2) {
                Text("\(timetable.station.name)  \(timetable.line.name)  \(timetable.direction.name)")
                Text("\(timetable.validFrom.description) から有効・平日 \(timetable.departures(for: .weekday).count) 本・土休日 \(timetable.departures(for: .holiday).count) 本")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("削除")
        }
    }
}
