import Foundation
import Testing
@testable import TimetableCore

private func departures(_ times: String...) -> [Departure] {
    times.map { Departure(time: ServiceTime(string: $0)!, type: "各停", destination: "××") }
}

private func makeTimetable(
    validFrom: String = "2026-03-14",
    weekday: [Departure],
    saturday: [Departure]? = nil,
    holiday: [Departure]
) -> Timetable {
    var calendars: [CalendarKind: [Departure]] = [.weekday: weekday, .holiday: holiday]
    calendars[.saturday] = saturday
    return Timetable(
        station: Station(id: "s", name: "〇〇駅"),
        line: Line(id: "l", name: "△△線"),
        direction: Direction(id: "d", name: "××方面"),
        validFrom: CalendarDate(string: validFrom)!,
        calendars: calendars)
}

@Suite struct DepartureServiceTests {
    let service = DepartureService(resolver: ServiceDayResolver(holidays: HolidayCalendar(names: [:])))

    // 2026-10-26 は月曜、2026-10-31 は土曜
    let timetable = makeTimetable(
        weekday: departures("05:12", "17:50", "18:05", "18:12", "18:20", "24:21"),
        holiday: departures("05:40", "18:30"))

    private func times(_ board: DepartureBoard?) -> [String] {
        board?.departures.map(\.departure.time.description) ?? []
    }

    @Test func returnsDeparturesFromNow() throws {
        let board = try #require(service.board(
            at: tokyoDate(2026, 10, 26, 18, 0), timetables: [timetable], minutesToStation: 0, count: 3))
        #expect(times(board) == ["18:05", "18:12", "18:20"])
        #expect(board.calendarKind == .weekday)
        #expect(board.serviceDay == CalendarDate(year: 2026, month: 10, day: 26))
        #expect(!board.isServiceEnded)
    }

    @Test func includesDepartureInCurrentMinute() throws {
        let board = try #require(service.board(
            at: tokyoDate(2026, 10, 26, 18, 5, 30), timetables: [timetable], minutesToStation: 0, count: 1))
        #expect(times(board) == ["18:05"])
        // 発車時刻を過ぎているので乗れない
        #expect(board.nextCatchable == nil)
    }

    @Test func computesLeaveByAndCatchable() throws {
        let now = tokyoDate(2026, 10, 26, 18, 0)
        let board = try #require(service.board(at: now, timetables: [timetable], minutesToStation: 8, count: 3))
        // 18:05 発は 17:57 に出発が必要なので間に合わない。18:12 発は 18:04 に出発すればよい
        #expect(board.departures.map(\.isCatchable) == [false, true, true])
        let next = try #require(board.nextCatchable)
        #expect(next.departure.time.description == "18:12")
        #expect(next.leaveByDate == tokyoDate(2026, 10, 26, 18, 4))
        #expect(next.secondsUntilLeave(from: now) == 4 * 60)
        #expect(next.secondsUntilDeparture(from: now) == 12 * 60)
    }

    @Test func leaveByExactlyNowIsCatchable() throws {
        let board = try #require(service.board(
            at: tokyoDate(2026, 10, 26, 17, 57), timetables: [timetable], minutesToStation: 8, count: 1))
        #expect(board.nextCatchable?.departure.time.description == "18:05")
    }

    @Test func fillsFromNextServiceDayNearLastTrain() throws {
        let board = try #require(service.board(
            at: tokyoDate(2026, 10, 26, 18, 25), timetables: [timetable], minutesToStation: 0, count: 3))
        #expect(times(board) == ["24:21", "05:12", "17:50"])
        #expect(board.departures.map(\.serviceDay.day) == [26, 27, 27])
        #expect(!board.isServiceEnded)
    }

    @Test func departureAfterMidnightIsOnNextCalendarDay() throws {
        let board = try #require(service.board(
            at: tokyoDate(2026, 10, 26, 23, 50), timetables: [timetable], minutesToStation: 0, count: 1))
        let last = try #require(board.departures.first)
        #expect(last.departure.time.description == "24:21")
        #expect(last.departureDate == tokyoDate(2026, 10, 27, 0, 21))
    }

    @Test func earlyMorningBeforeBoundaryStillShowsLastTrain() throws {
        let board = try #require(service.board(
            at: tokyoDate(2026, 10, 27, 0, 10), timetables: [timetable], minutesToStation: 0, count: 2))
        #expect(board.serviceDay == CalendarDate(year: 2026, month: 10, day: 26))
        #expect(times(board) == ["24:21", "05:12"])
    }

    @Test func afterLastTrainShowsNextFirstTrain() throws {
        let board = try #require(service.board(
            at: tokyoDate(2026, 10, 27, 0, 30), timetables: [timetable], minutesToStation: 0, count: 2))
        #expect(board.isServiceEnded)
        #expect(times(board) == ["05:12", "17:50"])
        #expect(board.departures.first?.departureDate == tokyoDate(2026, 10, 27, 5, 12))
    }

    @Test func nextServiceDayUsesItsOwnCalendar() throws {
        // 金曜の終電後、翌日（土曜）は土曜ダイヤがないので土休日ダイヤ
        let board = try #require(service.board(
            at: tokyoDate(2026, 10, 31, 1, 0), timetables: [timetable], minutesToStation: 0, count: 2))
        #expect(board.calendarKind == .weekday)
        #expect(board.isServiceEnded)
        #expect(times(board) == ["05:40", "18:30"])
        #expect(board.departures.allSatisfy { $0.calendarKind == .holiday })
    }

    @Test func usesSaturdayCalendarWhenAvailable() throws {
        let withSaturday = makeTimetable(
            weekday: departures("18:05"), saturday: departures("18:15"), holiday: departures("18:30"))
        let board = try #require(service.board(
            at: tokyoDate(2026, 10, 31, 18, 0), timetables: [withSaturday], minutesToStation: 0, count: 1))
        #expect(board.calendarKind == .saturday)
        #expect(times(board) == ["18:15"])
    }

    @Test func switchesTimetableOnRevisionDay() throws {
        let old = makeTimetable(validFrom: "2026-03-14", weekday: departures("18:05"), holiday: departures("18:30"))
        let revised = makeTimetable(validFrom: "2026-10-27", weekday: departures("06:00", "18:10"), holiday: departures("18:40"))
        let board = try #require(service.board(
            at: tokyoDate(2026, 10, 26, 18, 0), timetables: [revised, old], minutesToStation: 0, count: 3))
        #expect(times(board) == ["18:05", "06:00", "18:10"])
    }

    @Test func returnsNilWithoutEffectiveTimetable() {
        let future = makeTimetable(validFrom: "2027-01-01", weekday: departures("18:05"), holiday: departures("18:30"))
        #expect(service.board(at: tokyoDate(2026, 10, 26, 18, 0), timetables: [future], minutesToStation: 0, count: 3) == nil)
        #expect(service.board(at: tokyoDate(2026, 10, 26, 18, 0), timetables: [], minutesToStation: 0, count: 3) == nil)
    }

    @Test func appliesFilter() throws {
        let mixed = makeTimetable(
            weekday: [
                Departure(time: ServiceTime(hour: 18, minute: 5), type: "特急", destination: "××"),
                Departure(time: ServiceTime(hour: 18, minute: 12), type: "各停", destination: "××"),
            ],
            holiday: [])
        let filter = DepartureFilter { $0.type != "特急" }
        let board = try #require(service.board(
            at: tokyoDate(2026, 10, 26, 18, 0), timetables: [mixed], minutesToStation: 0, count: 3, filter: filter))
        #expect(times(board).prefix(1) == ["18:12"])
        #expect(!board.departures.contains { $0.departure.type == "特急" })
    }

    @Test func emptyTimetableReturnsEmptyBoard() throws {
        let empty = makeTimetable(weekday: [], holiday: [])
        let board = try #require(service.board(
            at: tokyoDate(2026, 10, 26, 18, 0), timetables: [empty], minutesToStation: 0, count: 3))
        #expect(board.departures.isEmpty)
        #expect(board.isServiceEnded)
    }
}

@Suite struct PartitioningIndexTests {
    @Test(arguments: [(0, 0), (1, 0), (3, 1), (4, 2), (9, 4), (10, 5)])
    func findsFirstIndex(threshold: Int, expected: Int) {
        let values = [1, 3, 5, 7, 9]
        #expect(values.partitioningIndex { $0 >= threshold } == expected)
    }
}
