import Foundation
import Testing
@testable import TimetableCore

private func json(
    version: Int = 1,
    validFrom: String = "2026-03-14",
    calendars: String = """
        "weekday": [
          { "time": "18:05", "type": "快速", "destination": "××" },
          { "time": "05:12", "type": "各停", "destination": "××" },
          { "time": "24:21", "type": "各停", "destination": "□□" }
        ],
        "holiday": [
          { "time": "05:20" }
        ]
        """
) -> Data {
    Data("""
        {
          "version": \(version),
          "station": { "id": "example-station", "name": "〇〇駅" },
          "line": { "id": "example-line", "name": "△△線" },
          "direction": { "id": "outbound", "name": "××方面" },
          "validFrom": "\(validFrom)",
          "source": "manual",
          "calendars": { \(calendars) }
        }
        """.utf8)
}

@Suite struct ServiceTimeTests {
    @Test(arguments: [
        ("05:12", 312),
        ("5:12", 312),
        ("00:00", 0),
        ("24:21", 1461),
        ("47:59", 2879),
    ])
    func parsesValidTimes(text: String, minutes: Int) throws {
        let time = try #require(ServiceTime(string: text))
        #expect(time.minutes == minutes)
    }

    @Test(arguments: ["", "18", "18:5", "18:60", "48:00", "-1:00", "18:05:00", "ab:cd", "１８:０５"])
    func rejectsInvalidTimes(text: String) {
        #expect(ServiceTime(string: text) == nil)
    }

    @Test func formatsServiceAndClockTimes() {
        let time = ServiceTime(hour: 24, minute: 5)
        #expect(time.description == "24:05")
        #expect(time.clockDescription == "00:05")
        #expect(ServiceTime(hour: 9, minute: 7).description == "09:07")
    }
}

@Suite struct CalendarDateTests {
    @Test func parsesAndFormats() throws {
        let date = try #require(CalendarDate(string: "2026-03-14"))
        #expect(date == CalendarDate(year: 2026, month: 3, day: 14))
        #expect(date.description == "2026-03-14")
    }

    @Test(arguments: ["2026-02-30", "2026-13-01", "2026/03/14", "26-03-14", ""])
    func rejectsInvalidDates(text: String) {
        #expect(CalendarDate(string: text) == nil)
    }

    @Test func addsDaysAcrossMonthAndYear() {
        #expect(CalendarDate(year: 2026, month: 12, day: 31).adding(days: 1) == CalendarDate(year: 2027, month: 1, day: 1))
        #expect(CalendarDate(year: 2026, month: 3, day: 1).adding(days: -1) == CalendarDate(year: 2026, month: 2, day: 28))
    }

    @Test func weekday() {
        // 2026-10-25 は日曜、2026-10-31 は土曜
        #expect(CalendarDate(year: 2026, month: 10, day: 25).weekday == 1)
        #expect(CalendarDate(year: 2026, month: 10, day: 31).weekday == 7)
    }
}

@Suite struct TimetableDecodingTests {
    @Test func decodesTimetableAndSortsDepartures() throws {
        let timetable = try Timetable.decode(from: json())
        #expect(timetable.station.name == "〇〇駅")
        #expect(timetable.line.name == "△△線")
        #expect(timetable.direction.name == "××方面")
        #expect(timetable.validFrom == CalendarDate(year: 2026, month: 3, day: 14))
        #expect(timetable.source == .manual)

        let weekday = timetable.departures(for: .weekday)
        #expect(weekday.map(\.time.description) == ["05:12", "18:05", "24:21"])
        #expect(weekday[1].type == "快速")
        #expect(weekday[2].destination == "□□")
        #expect(timetable.departures(for: .holiday).first?.type == nil)
    }

    @Test func saturdayIsOptional() throws {
        let timetable = try Timetable.decode(from: json())
        #expect(!timetable.hasSaturdayCalendar)
        #expect(timetable.departures(for: .saturday).isEmpty)

        let withSaturday = try Timetable.decode(from: json(calendars: """
            "weekday": [], "saturday": [{ "time": "06:00" }], "holiday": []
            """))
        #expect(withSaturday.hasSaturdayCalendar)
        #expect(withSaturday.departures(for: .saturday).count == 1)
    }

    @Test func roundTripsThroughJSON() throws {
        let timetable = try Timetable.decode(from: json())
        let decoded = try Timetable.decode(from: timetable.encoded())
        #expect(decoded == timetable)
    }

    @Test func rejectsInvalidTime() {
        #expect(throws: TimetableError.invalidTime("25:60")) {
            try Timetable.decode(from: json(calendars: #""weekday": [{ "time": "25:60" }], "holiday": []"#))
        }
    }

    @Test func rejectsUnknownCalendar() {
        #expect(throws: TimetableError.unknownCalendar("sunday")) {
            try Timetable.decode(from: json(calendars: #""weekday": [], "holiday": [], "sunday": []"#))
        }
    }

    @Test func rejectsMissingCalendar() {
        #expect(throws: TimetableError.missingCalendar(.holiday)) {
            try Timetable.decode(from: json(calendars: #""weekday": []"#))
        }
    }

    @Test func rejectsUnsupportedVersion() {
        #expect(throws: TimetableError.unsupportedVersion(2)) {
            try Timetable.decode(from: json(version: 2))
        }
    }

    @Test func rejectsMalformedJSON() {
        #expect {
            try Timetable.decode(from: Data("{".utf8))
        } throws: { error in
            if case .malformed = error as? TimetableError { true } else { false }
        }
        #expect {
            try Timetable.decode(from: json(validFrom: "2026-02-30"))
        } throws: { error in
            if case .malformed = error as? TimetableError { true } else { false }
        }
    }
}

@Suite struct EffectiveTimetableTests {
    private func timetable(validFrom: String) throws -> Timetable {
        try Timetable.decode(from: json(validFrom: validFrom))
    }

    @Test func selectsLatestTimetableValidOnDate() throws {
        let old = try timetable(validFrom: "2025-03-15")
        let current = try timetable(validFrom: "2026-03-14")
        let future = try timetable(validFrom: "2027-03-13")
        let candidates = [future, old, current]

        #expect(Timetable.effective(among: candidates, on: CalendarDate(year: 2026, month: 10, day: 25)) == current)
        #expect(Timetable.effective(among: candidates, on: CalendarDate(year: 2026, month: 3, day: 13)) == old)
        #expect(Timetable.effective(among: candidates, on: CalendarDate(year: 2027, month: 3, day: 13)) == future)
    }

    @Test func returnsNilBeforeAnyTimetable() throws {
        let current = try timetable(validFrom: "2026-03-14")
        #expect(Timetable.effective(among: [current], on: CalendarDate(year: 2026, month: 3, day: 13)) == nil)
        #expect(Timetable.effective(among: [], on: CalendarDate(year: 2026, month: 3, day: 13)) == nil)
    }
}
