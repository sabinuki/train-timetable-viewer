import SwiftUI
import TimetableCore

/// フローティングパネルの中身（設計書 §6.2）
struct DeparturePanelView: View {
    let viewModel: DepartureBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            content
        }
        .padding(.horizontal, 14)
        .padding(.top, 2)  // タイトルバー（× ボタン）の分は safe area で空く
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, ignoresSafeAreaEdges: .all)
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.status {
        case .noTimetable:
            message("時刻表が取り込まれていません", detail: "メニューバーの「設定…」から時刻表 JSON を取り込んでください")
        case .notYetEffective(let date):
            message("時刻表は \(date.description) から有効です", detail: nil)
        case .ready:
            if let timetable = viewModel.timetable, let board = viewModel.board {
                header(timetable: timetable, board: board)
                Divider()
                if board.isServiceEnded {
                    Text("本日の運行は終了しました")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                departures(board)
            }
        }
    }

    private func header(timetable: Timetable, board: DepartureBoard) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(timetable.station.name).font(.headline)
            Text(timetable.line.name)
            Text(timetable.direction.name)
            Spacer(minLength: 4)
            Text(board.calendarKind.displayName)
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
        }
        .lineLimit(1)
    }

    private func departures(_ board: DepartureBoard) -> some View {
        let highlightedID = board.nextCatchable?.id
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(board.departures) { upcoming in
                DepartureRow(
                    upcoming: upcoming,
                    isHighlighted: upcoming.id == highlightedID,
                    showsLeaveBy: viewModel.minutesToStation > 0,
                    viewModel: viewModel)
            }
        }
    }

    private func message(_ title: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if let detail {
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}

private struct DepartureRow: View {
    let upcoming: UpcomingDeparture
    let isHighlighted: Bool
    let showsLeaveBy: Bool
    let viewModel: DepartureBoardViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "play.fill")
                    .font(.caption2)
                    .opacity(isHighlighted ? 1 : 0)
                Text(upcoming.departure.time.clockDescription)
                    .font(isHighlighted ? .title2.bold() : .body)
                if let type = upcoming.departure.type {
                    Text(type)
                }
                if let destination = upcoming.departure.destination {
                    Text("\(destination)行")
                }
                Spacer(minLength: 4)
                Text(viewModel.remainingText(until: upcoming.departureDate))
                    .font(isHighlighted ? .body.bold() : .body)
            }
            if isHighlighted && showsLeaveBy {
                Text("└ \(viewModel.clockText(upcoming.leaveByDate)) までに出発（\(viewModel.remainingText(until: upcoming.leaveByDate))）")
                    .font(.callout)
                    .foregroundStyle(.tint)
                    .padding(.leading, 22)
            }
        }
        .monospacedDigit()
        .lineLimit(1)
        .foregroundStyle(isHighlighted ? .primary : .secondary)
        .opacity(upcoming.isCatchable ? 1 : 0.4)
    }
}
