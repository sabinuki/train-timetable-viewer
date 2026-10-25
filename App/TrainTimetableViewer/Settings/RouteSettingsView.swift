import SwiftUI
import TimetableCore
import UniformTypeIdentifiers

/// 「路線」タブ: 路線プロファイルと時刻表
struct RouteSettingsView: View {
    let model: AppModel

    @State private var isImporting = false
    @State private var error: SettingsError?
    @State private var importedMessage: String?

    private var viewModel: DepartureBoardViewModel { model.viewModel }

    var body: some View {
        Form {
            profileSection
            timetableSection
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                importTimetable(from: url)
            case .failure(let failure):
                error = SettingsError(title: "時刻表を取り込めません", message: failure.localizedDescription)
            }
        }
        .settingsErrorAlert($error)
    }

    // MARK: - 路線プロファイル

    @ViewBuilder
    private var profileSection: some View {
        Section {
            if viewModel.profiles.isEmpty {
                Text("時刻表を取り込むと、プロファイルが作られます")
                    .foregroundStyle(.secondary)
            } else {
                Picker("表示中のプロファイル", selection: Binding(
                    get: { viewModel.selectedProfileID },
                    set: { id in if let id { viewModel.selectProfile(id) } }
                )) {
                    ForEach(viewModel.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
            }

            if let profile = viewModel.selectedProfile {
                TextField("名前", text: binding(for: profile, \.name))
                Picker("時刻表", selection: binding(for: profile, \.routeKey)) {
                    Text("未設定").tag(String?.none)
                    ForEach(viewModel.routes.keys.sorted(), id: \.self) { routeKey in
                        Text(routeLabel(routeKey)).tag(Optional(routeKey))
                    }
                }
                Stepper(value: binding(for: profile, \.minutesToStation), in: AppSettings.minutesToStationRange) {
                    LabeledContent("駅までの所要時間") {
                        HStack(spacing: 4) {
                            TextField("所要時間", value: binding(for: profile, \.minutesToStation), format: .number)
                                .labelsHidden()
                                .multilineTextAlignment(.trailing)
                                .frame(width: 48)
                            Text("分")
                        }
                    }
                }
            }

            HStack {
                Button("プロファイルを追加") { viewModel.addProfile() }
                    .disabled(viewModel.routes.isEmpty)
                if let profile = viewModel.selectedProfile {
                    Button("このプロファイルを削除", role: .destructive) {
                        viewModel.deleteProfile(profile.id)
                    }
                }
            }
        } header: {
            Text("路線プロファイル")
        } footer: {
            Text("「職場から帰る」「自宅から出かける」のように、場面ごとに駅・方面と駅までの所要時間を登録できます。メニューバーの「路線切替」からも切り替えられます。発車時刻から所要時間を引いた時刻を「出発すべき時刻」として表示します")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func binding<Value>(for profile: RouteProfile, _ keyPath: WritableKeyPath<RouteProfile, Value>) -> Binding<Value> {
        Binding(
            get: { viewModel.selectedProfile?[keyPath: keyPath] ?? profile[keyPath: keyPath] },
            set: { newValue in
                guard var current = viewModel.selectedProfile else { return }
                current[keyPath: keyPath] = newValue
                viewModel.updateProfile(current)
            })
    }

    private func routeLabel(_ routeKey: String) -> String {
        guard let timetable = viewModel.routes[routeKey]?.first else { return routeKey }
        return "\(timetable.station.name) \(timetable.line.name) \(timetable.direction.name)"
    }

    // MARK: - 時刻表

    private var timetableSection: some View {
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
    }

    private func importTimetable(from url: URL) {
        Task {
            do {
                let timetable = try await model.importTimetable(from: url)
                importedMessage = "\(timetable.station.name) \(timetable.line.name) \(timetable.direction.name)（\(timetable.validFrom.description) から）を取り込みました"
            } catch let failure {
                error = SettingsError(title: "時刻表を取り込めません", message: failure.localizedDescription)
            }
        }
    }

    private func delete(_ timetable: Timetable) {
        do {
            try model.deleteTimetable(timetable)
            importedMessage = nil
        } catch let failure {
            error = SettingsError(title: "時刻表を削除できません", message: failure.localizedDescription)
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
