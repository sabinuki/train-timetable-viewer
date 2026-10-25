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
        #expect(AppSettings(defaults: defaults).profiles?.first?.minutesToStation == 8)

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

    @Test func createsProfileForFirstRoute() throws {
        viewModel.load([makeTimetable(station: "b"), makeTimetable(station: "a")])
        #expect(viewModel.profiles.count == 1)
        let profile = try #require(viewModel.selectedProfile)
        #expect(profile.routeKey == "a/l/d")
        #expect(profile.name == "a駅 ××方面")
        #expect(AppSettings(defaults: defaults).profiles == viewModel.profiles)
        #expect(AppSettings(defaults: defaults).selectedProfileID == profile.id)
    }

    @Test func noProfileBeforeFirstImport() {
        viewModel.load([])
        #expect(viewModel.profiles.isEmpty)
        #expect(viewModel.selectedProfile == nil)
        // プロファイルがなくても所要時間の変更でクラッシュしない
        viewModel.minutesToStation = 5
        #expect(viewModel.minutesToStation == 0)
    }

    @Test func switchingProfileChangesRouteAndMinutes() throws {
        viewModel.load([makeTimetable(station: "a"), makeTimetable(station: "b")])
        let home = try #require(viewModel.selectedProfile)
        viewModel.minutesToStation = 8

        let office = viewModel.addProfile(routeKey: "b/l/d")
        #expect(viewModel.selectedProfileID == office.id)
        #expect(viewModel.timetable?.station.id == "b")
        #expect(viewModel.minutesToStation == 0)
        #expect(viewModel.menuBarTitle == "18:05 あと5分")

        viewModel.selectProfile(home.id)
        #expect(viewModel.timetable?.station.id == "a")
        #expect(viewModel.minutesToStation == 8)
        #expect(viewModel.menuBarTitle == "18:12 あと12分")
        #expect(AppSettings(defaults: defaults).selectedProfileID == home.id)

        // 未知の ID は無視する
        viewModel.selectProfile(UUID())
        #expect(viewModel.selectedProfileID == home.id)
    }

    @Test func profilesSurviveRelaunch() throws {
        viewModel.load([makeTimetable(station: "a"), makeTimetable(station: "b")])
        let office = viewModel.addProfile(routeKey: "b/l/d")
        var renamed = office
        renamed.name = "職場から帰る"
        renamed.minutesToStation = 12
        viewModel.updateProfile(renamed)

        let relaunched = DepartureBoardViewModel(
            service: DepartureService(resolver: ServiceDayResolver(holidays: HolidayCalendar(names: [:]))),
            settings: AppSettings(defaults: defaults),
            now: { tokyoDate(2026, 10, 26, 18, 0) })
        relaunched.load([makeTimetable(station: "a"), makeTimetable(station: "b")])
        #expect(relaunched.profiles.count == 2)
        #expect(relaunched.selectedProfile?.name == "職場から帰る")
        #expect(relaunched.minutesToStation == 12)
        #expect(relaunched.timetable?.station.id == "b")
    }

    @Test func showRouteSelectsAssignsOrCreatesProfile() throws {
        viewModel.load([makeTimetable(station: "a")])
        let first = try #require(viewModel.selectedProfile)

        // 新しい路線を取り込むと、新しいプロファイルができて表示される
        viewModel.load([makeTimetable(station: "a"), makeTimetable(station: "b")])
        viewModel.showRoute("b/l/d")
        #expect(viewModel.profiles.count == 2)
        #expect(viewModel.selectedRouteKey == "b/l/d")

        // 既存の路線を取り込み直すと、そのプロファイルに切り替わる
        viewModel.showRoute("a/l/d")
        #expect(viewModel.profiles.count == 2)
        #expect(viewModel.selectedProfileID == first.id)

        // 時刻表のないプロファイルを表示中に取り込むと、そのプロファイルに割り当てる
        let empty = viewModel.addProfile(routeKey: nil)
        var unassigned = empty
        unassigned.routeKey = nil
        viewModel.updateProfile(unassigned)
        viewModel.load([makeTimetable(station: "a"), makeTimetable(station: "b"), makeTimetable(station: "c")])
        viewModel.showRoute("c/l/d")
        #expect(viewModel.profiles.count == 3)
        #expect(viewModel.selectedProfileID == empty.id)
        #expect(viewModel.selectedRouteKey == "c/l/d")
    }

    @Test func deletingSelectedProfileSelectsFirst() throws {
        viewModel.load([makeTimetable(station: "a"), makeTimetable(station: "b")])
        let first = try #require(viewModel.selectedProfile)
        let second = viewModel.addProfile(routeKey: "b/l/d")
        viewModel.deleteProfile(second.id)
        #expect(viewModel.profiles.map(\.id) == [first.id])
        #expect(viewModel.selectedProfileID == first.id)

        viewModel.deleteProfile(first.id)
        #expect(viewModel.profiles.isEmpty)
        #expect(viewModel.status == .noTimetable)
    }

    @Test func profileWhoseTimetableWasDeletedShowsNoTimetable() {
        viewModel.load([makeTimetable(station: "a")])
        viewModel.load([])
        #expect(viewModel.profiles.count == 1)
        #expect(viewModel.status == .noTimetable)
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

@MainActor
@Suite struct ProfileMigrationTests {
    @Test func migratesLegacySingleSettings() throws {
        let suite = "ProfileMigrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        // #19 より前の設定
        defaults.set(8, forKey: "minutesToStation")
        defaults.set("b/l/d", forKey: "selectedRouteKey")

        let viewModel = DepartureBoardViewModel(
            service: DepartureService(resolver: ServiceDayResolver(holidays: HolidayCalendar(names: [:]))),
            settings: AppSettings(defaults: defaults),
            now: { tokyoDate(2026, 10, 26, 18, 0) })
        viewModel.load([makeTimetable(station: "a"), makeTimetable(station: "b")])

        #expect(viewModel.profiles.count == 1)
        let profile = try #require(viewModel.selectedProfile)
        #expect(profile.routeKey == "b/l/d")
        #expect(profile.minutesToStation == 8)
        #expect(profile.name == "b駅 ××方面")
        #expect(AppSettings(defaults: defaults).profiles == [profile])
    }
}

@Suite struct AppSettingsTests {
    private func makeSettings() -> AppSettings {
        let suite = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return AppSettings(defaults: defaults)
    }

    @Test func defaults() {
        let settings = makeSettings()
        #expect(settings.profiles == nil)
        #expect(settings.selectedProfileID == nil)
        #expect(settings.isPanelVisible)
        #expect(settings.displayCount == AppSettings.defaultDisplayCount)
        #expect(settings.panelOpacity == 1.0)
        #expect(!settings.isClickThrough)
    }

    @Test func clampsAndPersistsPanelAppearance() {
        let settings = makeSettings()
        settings.panelOpacity = 0.5
        #expect(AppSettings(defaults: settings.defaults).panelOpacity == 0.5)
        settings.panelOpacity = 0.1
        #expect(settings.panelOpacity == AppSettings.panelOpacityRange.lowerBound)
        settings.panelOpacity = 2
        #expect(settings.panelOpacity == AppSettings.panelOpacityRange.upperBound)

        settings.isClickThrough = true
        #expect(AppSettings(defaults: settings.defaults).isClickThrough)
    }

    @Test func persistsPanelVisibility() {
        let settings = makeSettings()
        settings.isPanelVisible = false
        #expect(!AppSettings(defaults: settings.defaults).isPanelVisible)
        settings.isPanelVisible = true
        #expect(AppSettings(defaults: settings.defaults).isPanelVisible)
    }
}
