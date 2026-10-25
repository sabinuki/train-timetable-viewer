import Foundation
import Testing
@testable import TimetableCore

/// テストから進められる時計
@MainActor
private final class TestClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

private func makeTimetable(station: String = "s", validFrom: String = "2026-03-14") -> Timetable {
    Timetable(
        station: Station(id: station, name: "\(station)駅"),
        line: Line(id: "l", name: "△△線"),
        direction: Direction(id: "d", name: "××方面"),
        validFrom: CalendarDate(string: validFrom)!,
        calendars: [
            .weekday: ["05:12", "18:05", "18:12", "18:20", "24:21"].map { Departure(time: ServiceTime(string: $0)!, type: "各停") },
            .holiday: [Departure(time: ServiceTime(hour: 6, minute: 0))],
        ])
}

@MainActor
@Suite struct DepartureBoardViewModelTests {
    private let defaults: UserDefaults
    private let clock = TestClock(tokyoDate(2026, 10, 26, 18, 0))
    private let viewModel: DepartureBoardViewModel

    init() {
        let suite = "DepartureBoardViewModelTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let clock = clock
        viewModel = DepartureBoardViewModel(
            service: DepartureService(resolver: ServiceDayResolver(holidays: HolidayCalendar(names: [:]))),
            settings: AppSettings(defaults: defaults),
            now: { clock.date })
    }

    @Test func noTimetableBeforeImport() {
        viewModel.load([])
        #expect(viewModel.status == .noTimetable)
        #expect(viewModel.board == nil)
        #expect(viewModel.menuBarTitle == "時刻表なし")
    }

    @Test func showsUpcomingDepartures() throws {
        viewModel.load([makeTimetable()])
        #expect(viewModel.status == .ready)
        #expect(viewModel.timetable?.station.name == "s駅")
        let board = try #require(viewModel.board)
        #expect(board.calendarKind == .weekday)
        #expect(board.departures.map(\.departure.time.description) == ["18:05", "18:12", "18:20", "24:21", "05:12"])
        #expect(viewModel.menuBarTitle == "18:05 あと5分")
    }

    @Test func minutesToStationChangesNextCatchableAndIsSaved() throws {
        viewModel.load([makeTimetable()])
        viewModel.minutesToStation = 8
        #expect(viewModel.headlineDeparture?.departure.time.description == "18:12")
        #expect(viewModel.menuBarTitle == "18:12 あと12分")
        #expect(viewModel.clockText(try #require(viewModel.headlineDeparture).leaveByDate) == "18:04")
        #expect(AppSettings(defaults: defaults).minutesToStation == 8)

        viewModel.minutesToStation = 500
        #expect(viewModel.minutesToStation == AppSettings.minutesToStationRange.upperBound)
    }

    @Test func refreshUsesCurrentTime() {
        viewModel.load([makeTimetable()])
        clock.date = tokyoDate(2026, 10, 26, 18, 6)
        // 再計算するまでは前の結果のまま
        #expect(viewModel.menuBarTitle == "18:05 あと5分")
        viewModel.refresh()
        #expect(viewModel.menuBarTitle == "18:12 あと6分")
    }

    @Test func refreshAfterWakeAcrossDays() throws {
        viewModel.load([makeTimetable()])
        // スリープ中に日付が変わり、土曜の朝に復帰した
        clock.date = tokyoDate(2026, 10, 31, 9, 0)
        viewModel.refresh()
        let board = try #require(viewModel.board)
        #expect(board.serviceDay == CalendarDate(year: 2026, month: 10, day: 31))
        #expect(board.calendarKind == .holiday)
    }

    @Test func showsFirstTrainAfterServiceEnds() {
        viewModel.load([makeTimetable()])
        clock.date = tokyoDate(2026, 10, 27, 1, 0)
        viewModel.refresh()
        #expect(viewModel.board?.isServiceEnded == true)
        #expect(viewModel.menuBarTitle == "始発 05:12")
    }

    @Test func notYetEffectiveTimetable() {
        viewModel.load([makeTimetable(validFrom: "2027-03-13")])
        #expect(viewModel.status == .notYetEffective(CalendarDate(year: 2027, month: 3, day: 13)))
        #expect(viewModel.menuBarTitle == "3/13 から")
    }

    @Test func selectsRouteAndRemembersIt() {
        viewModel.load([makeTimetable(station: "a"), makeTimetable(station: "b")])
        #expect(viewModel.selectedRouteKey == "a/l/d")
        viewModel.selectRoute("b/l/d")
        #expect(viewModel.timetable?.station.id == "b")
        #expect(AppSettings(defaults: defaults).selectedRouteKey == "b/l/d")

        // 未知の路線は無視する
        viewModel.selectRoute("unknown")
        #expect(viewModel.selectedRouteKey == "b/l/d")

        // 選択中の路線が削除されたら最初の路線に戻る
        viewModel.load([makeTimetable(station: "a")])
        #expect(viewModel.selectedRouteKey == "a/l/d")
    }

    @Test func remainingText() {
        viewModel.load([makeTimetable()])
        #expect(viewModel.remainingText(until: tokyoDate(2026, 10, 26, 18, 12)) == "あと12分")
        #expect(viewModel.remainingText(until: tokyoDate(2026, 10, 26, 18, 0, 30)) == "まもなく")
        #expect(viewModel.remainingText(until: tokyoDate(2026, 10, 26, 19, 30)) == "あと1時間30分")
        #expect(viewModel.remainingText(until: tokyoDate(2026, 10, 26, 17, 59)) == "発車済み")
    }
}

@Suite struct NextMinuteBoundaryTests {
    @Test func roundsUpToNextMinute() {
        #expect(nextMinuteBoundary(after: tokyoDate(2026, 10, 26, 18, 0, 0)) == tokyoDate(2026, 10, 26, 18, 1, 0))
        #expect(nextMinuteBoundary(after: tokyoDate(2026, 10, 26, 18, 0, 59)) == tokyoDate(2026, 10, 26, 18, 1, 0))
        #expect(nextMinuteBoundary(after: tokyoDate(2026, 10, 26, 23, 59, 30)) == tokyoDate(2026, 10, 27, 0, 0, 0))
    }
}
