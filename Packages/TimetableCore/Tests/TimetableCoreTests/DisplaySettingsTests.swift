import Foundation
import Testing
@testable import TimetableCore

@MainActor
private final class MutableClock {
    var date: Date
    init(_ date: Date) { self.date = date }
}

@MainActor
@Suite struct DisplaySettingsTests {
    private let defaults: UserDefaults
    private let clock = MutableClock(tokyoDate(2026, 10, 26, 18, 0, 0))
    private let viewModel: DepartureBoardViewModel

    private let timetable = Timetable(
        station: Station(id: "s", name: "〇〇駅"),
        line: Line(id: "l", name: "△△線"),
        direction: Direction(id: "d", name: "××方面"),
        validFrom: CalendarDate(year: 2026, month: 3, day: 14),
        calendars: [
            .weekday: (0..<20).map { Departure(time: ServiceTime(hour: 18, minute: 5 + $0 * 2)) },
            .holiday: [Departure(time: ServiceTime(hour: 18, minute: 30))],
        ])

    init() {
        let suite = "DisplaySettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let clock = clock
        viewModel = DepartureBoardViewModel(
            service: DepartureService(resolver: ServiceDayResolver(holidays: HolidayCalendar(names: [:]))),
            settings: AppSettings(defaults: defaults),
            now: { clock.date })
        viewModel.load([timetable])
    }

    private func relaunched() -> DepartureBoardViewModel {
        let viewModel = DepartureBoardViewModel(
            service: DepartureService(resolver: ServiceDayResolver(holidays: HolidayCalendar(names: [:]))),
            settings: AppSettings(defaults: defaults),
            now: { tokyoDate(2026, 10, 26, 18, 0) })
        viewModel.load([timetable])
        return viewModel
    }

    @Test func displayCountChangesNumberOfDeparturesAndPersists() {
        #expect(viewModel.board?.departures.count == AppSettings.defaultDisplayCount)
        viewModel.displayCount = 8
        #expect(viewModel.board?.departures.count == 8)
        #expect(relaunched().displayCount == 8)

        AppSettings(defaults: defaults).displayCount = 50
        #expect(AppSettings(defaults: defaults).displayCount == AppSettings.displayCountRange.upperBound)
    }

    @Test func menuBarStyles() {
        viewModel.minutesToStation = 3
        #expect(viewModel.menuBarTitle == "18:05 あと5分")
        viewModel.menuBarStyle = .leaveBy
        #expect(viewModel.menuBarTitle == "18:02 出発 あと2分")
        viewModel.menuBarStyle = .iconOnly
        #expect(viewModel.menuBarTitle == "")
        #expect(relaunched().menuBarStyle == .iconOnly)
    }

    @Test func secondsCountdown() {
        clock.date = tokyoDate(2026, 10, 26, 18, 0, 15)
        viewModel.showsSeconds = true
        #expect(viewModel.menuBarTitle == "18:05 あと4分45秒")
        #expect(viewModel.remainingText(until: tokyoDate(2026, 10, 26, 18, 0, 45)) == "あと30秒")
        #expect(viewModel.remainingText(until: tokyoDate(2026, 10, 26, 19, 1, 15)) == "あと1時間1分0秒")
        #expect(relaunched().showsSeconds)
    }

    @Test func additionalHolidaysSwitchCalendar() {
        #expect(viewModel.board?.calendarKind == .weekday)
        viewModel.additionalHolidays = [CalendarDate(year: 2026, month: 10, day: 26)]
        #expect(viewModel.board?.calendarKind == .holiday)
        #expect(viewModel.menuBarTitle == "18:30 あと30分")
        #expect(relaunched().board?.calendarKind == .holiday)
    }

    @Test func hotKeySettingPersists() {
        let settings = AppSettings(defaults: defaults)
        #expect(settings.hotKey == .default)
        let custom = HotKeySetting(keyCode: 0x23, carbonModifiers: 0x1100, label: "⌃⌘P")
        settings.hotKey = custom
        #expect(AppSettings(defaults: defaults).hotKey == custom)
    }

    @Test func nextSecond() {
        let date = Date(timeIntervalSinceReferenceDate: 100.4)
        #expect(nextSecondBoundary(after: date) == Date(timeIntervalSinceReferenceDate: 101))
    }
}
