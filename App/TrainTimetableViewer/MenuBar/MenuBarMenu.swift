import SwiftUI
import TimetableCore

/// メニューバーのメニュー（設計書 §6.1）
struct MenuBarMenu: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

    private var viewModel: DepartureBoardViewModel { model.viewModel }

    var body: some View {
        summary
        Divider()
        Button(model.isPanelVisible ? "パネルを隠す" : "パネルを表示") {
            model.togglePanel()
        }
        .keyboardShortcut("t", modifiers: [.option, .command])
        .disabled(!model.canShowPanel)
        Button("設定…") {
            openSettings()
            NSApplication.shared.activate()
        }
        .keyboardShortcut(",")
        Divider()
        Button("終了") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    @ViewBuilder
    private var summary: some View {
        switch viewModel.status {
        case .noTimetable:
            Text("時刻表が取り込まれていません")
            Text("「設定…」から時刻表 JSON を取り込んでください")
        case .notYetEffective(let date):
            Text("取り込んだ時刻表は \(date.description) から有効です")
        case .ready:
            if let timetable = viewModel.timetable, let board = viewModel.board {
                Text("\(timetable.station.name)  \(timetable.line.name)  \(timetable.direction.name)  \(board.calendarKind.displayName)")
                if board.isServiceEnded {
                    Text("本日の運行は終了しました")
                }
                ForEach(board.departures.prefix(3)) { upcoming in
                    Text(line(for: upcoming))
                }
            }
        }
    }

    private func line(for upcoming: UpcomingDeparture) -> String {
        let departure = upcoming.departure
        let label = [departure.type, departure.destination.map { "\($0)行" }].compactMap(\.self).joined(separator: " ")
        let remaining = viewModel.remainingText(until: upcoming.departureDate)
        return "\(departure.time.clockDescription)  \(label)  \(remaining)"
    }
}
