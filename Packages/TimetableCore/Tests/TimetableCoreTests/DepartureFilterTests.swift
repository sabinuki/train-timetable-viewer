import Foundation
import Testing
@testable import TimetableCore

private let timetable = Timetable(
    station: Station(id: "s", name: "〇〇駅"),
    line: Line(id: "l", name: "△△線"),
    direction: Direction(id: "d", name: "××方面"),
    validFrom: CalendarDate(year: 2026, month: 3, day: 14),
    calendars: [
        .weekday: [
            Departure(time: ServiceTime(hour: 18, minute: 2), type: "特急", destination: "××"),
            Departure(time: ServiceTime(hour: 18, minute: 5), type: "快速", destination: "××"),
            Departure(time: ServiceTime(hour: 18, minute: 8), type: "各停", destination: "□□"),
            Departure(time: ServiceTime(hour: 18, minute: 12), type: "各停", destination: "××"),
            Departure(time: ServiceTime(hour: 18, minute: 15)),
        ],
        .holiday: [Departure(time: ServiceTime(hour: 6, minute: 0), type: "快速", destination: "◇◇")],
    ])

@Suite struct DepartureFilterTests {
    let service = DepartureService(resolver: ServiceDayResolver(holidays: HolidayCalendar(names: [:])))

    private func times(_ filter: DepartureFilter) -> [String] {
        service.board(at: tokyoDate(2026, 10, 26, 18, 0), timetables: [timetable], minutesToStation: 0, count: 5, filter: filter)?
            .departures.map(\.departure.time.description) ?? []
    }

    @Test func noExclusionsKeepsEverything() {
        #expect(times(DepartureFilter(excludedTypes: [], excludedDestinations: [])) == ["18:02", "18:05", "18:08", "18:12", "18:15"])
    }

    @Test func excludesTypes() {
        #expect(times(DepartureFilter(excludedTypes: ["特急"], excludedDestinations: [])).prefix(4) == ["18:05", "18:08", "18:12", "18:15"])
    }

    @Test func excludesDestinations() {
        #expect(times(DepartureFilter(excludedTypes: [], excludedDestinations: ["□□"])).prefix(4) == ["18:02", "18:05", "18:12", "18:15"])
    }

    @Test func excludesBothAndKeepsDeparturesWithoutLabels() {
        let filtered = times(DepartureFilter(excludedTypes: ["特急", "快速"], excludedDestinations: ["□□"]))
        // 種別・行き先のない 18:15 発は残る。不足分は翌日（土休日ではなく火曜の平日ダイヤ）から補う
        #expect(filtered.prefix(2) == ["18:12", "18:15"])
        #expect(!filtered.contains("18:02") && !filtered.contains("18:05") && !filtered.contains("18:08"))
    }
}

@MainActor
@Suite struct ProfileFilterTests {
    private let defaults: UserDefaults
    private let viewModel: DepartureBoardViewModel

    init() {
        let suite = "ProfileFilterTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        viewModel = DepartureBoardViewModel(
            service: DepartureService(resolver: ServiceDayResolver(holidays: HolidayCalendar(names: [:]))),
            settings: AppSettings(defaults: defaults),
            now: { tokyoDate(2026, 10, 26, 18, 0) })
    }

    @Test func profileExclusionsApplyToMenuBarAndNotification() throws {
        viewModel.load([timetable])
        #expect(viewModel.menuBarTitle == "18:02 あと2分")

        var profile = try #require(viewModel.selectedProfile)
        profile.excludedTypes = ["特急"]
        profile.notification = NotificationSettings(isEnabled: true, minutesBefore: 0, windowStart: 0, windowEnd: 0)
        viewModel.updateProfile(profile)

        #expect(viewModel.menuBarTitle == "18:05 あと5分")
        #expect(!(viewModel.board?.departures.contains { $0.departure.type == "特急" } ?? true))
        // 通知も除外後の発車が対象になる
        #expect(viewModel.plannedNotification?.title.hasPrefix("18:05") == true)
        // 再起動後も保たれる
        #expect(AppSettings(defaults: defaults).profiles?.first?.excludedTypes == ["特急"])
    }

    @Test func filterCandidatesListTypesAndDestinationsOfSelectedRoute() {
        viewModel.load([timetable])
        #expect(viewModel.filterCandidates.types == ["各停", "快速", "特急"])
        #expect(viewModel.filterCandidates.destinations == ["××", "□□", "◇◇"])
    }

    @Test func decodesProfileSavedBeforeFiltersExisted() throws {
        let json = #"{"id":"C992A245-DD47-45E1-B4A9-DD1A63FE09B5","name":"p","routeKey":"s/l/d","minutesToStation":8,"notification":{"isEnabled":true,"minutesBefore":5,"windowStart":1020,"windowEnd":1200}}"#
        let profile = try JSONDecoder().decode(RouteProfile.self, from: Data(json.utf8))
        #expect(profile.excludedTypes.isEmpty)
        #expect(profile.excludedDestinations.isEmpty)
        #expect(profile.notification.isEnabled)
    }
}
