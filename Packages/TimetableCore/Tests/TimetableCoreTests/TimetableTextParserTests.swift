import Testing
@testable import TimetableCore

private let header = """
    station: example-station 〇〇駅
    line: example-line △△線
    direction: outbound ××方面
    validFrom: 2026-03-14
    type: 快=快速, 特=特急
    type-default: 各停
    destination: □=□□
    destination-default: ××

    """

@Suite struct TimetableTextParserTests {
    @Test func parsesTimetable() throws {
        let timetable = try TimetableTextParser.parse(header + """
            [weekday]   # 平日
            5: 12 30
            18: 05快 12 20快□ 31特
            24: 21□

            [holiday]
            06: 00
            """)

        #expect(timetable.station == Station(id: "example-station", name: "〇〇駅"))
        #expect(timetable.line == Line(id: "example-line", name: "△△線"))
        #expect(timetable.direction == Direction(id: "outbound", name: "××方面"))
        #expect(timetable.validFrom == CalendarDate(year: 2026, month: 3, day: 14))
        #expect(timetable.source == .manual)
        #expect(!timetable.hasSaturdayCalendar)

        let weekday = timetable.departures(for: .weekday)
        #expect(weekday.map(\.time.description) == ["05:12", "05:30", "18:05", "18:12", "18:20", "18:31", "24:21"])
        #expect(weekday[2] == Departure(time: ServiceTime(hour: 18, minute: 5), type: "快速", destination: "××"))
        #expect(weekday[3] == Departure(time: ServiceTime(hour: 18, minute: 12), type: "各停", destination: "××"))
        #expect(weekday[4] == Departure(time: ServiceTime(hour: 18, minute: 20), type: "快速", destination: "□□"))
        #expect(weekday[5].type == "特急")
        #expect(weekday[6].destination == "□□")
        #expect(timetable.departures(for: .holiday).count == 1)
    }

    @Test func parsesSaturdayAndEmptySections() throws {
        let timetable = try TimetableTextParser.parse(header + """
            [weekday]
            [saturday]
            7: 00
            [holiday]
            """)
        #expect(timetable.hasSaturdayCalendar)
        #expect(timetable.departures(for: .weekday).isEmpty)
        #expect(timetable.departures(for: .saturday).count == 1)
    }

    @Test func defaultsAreOptional() throws {
        let timetable = try TimetableTextParser.parse("""
            station: s 駅
            line: l 線
            direction: d 方面
            validFrom: 2026-03-14
            [weekday]
            7: 00
            [holiday]
            """)
        let departure = try #require(timetable.departures(for: .weekday).first)
        #expect(departure.type == nil)
        #expect(departure.destination == nil)
    }

    @Test func resultRoundTripsThroughJSON() throws {
        let timetable = try TimetableTextParser.parse(header + "[weekday]\n18: 05快□\n[holiday]\n")
        #expect(try Timetable.decode(from: timetable.encoded()) == timetable)
    }

    @Test(arguments: [
        ("[weekday]\n18: 05★\n[holiday]\n", TimetableTextError.unknownMark(line: 10, mark: "★")),
        ("[weekday]\n18: 60\n[holiday]\n", .invalidTime(line: 10, text: "60")),
        ("[weekday]\n18: 5x5\n[holiday]\n", .unknownMark(line: 10, mark: "x")),
        ("[weekday]\n48: 00\n[holiday]\n", .invalidTime(line: 10, text: "48")),
        ("[weekday]\n", .missingSection(.holiday)),
        ("[weekday]\n[weekday]\n[holiday]\n", .duplicateSection(line: 10, kind: .weekday)),
        ("[sunday]\n", .invalidSection(line: 9, text: "[sunday]")),
        ("18: 05\n", .departureOutsideSection(line: 9)),
        ("[weekday]\nline: x 線\n[holiday]\n", .headerInsideSection(line: 10, key: "line")),
        ("color: red\n", .unknownKey(line: 9, key: "color")),
        ("これは何\n", .invalidLine(line: 9, text: "これは何")),
    ])
    func reportsErrors(body: String, expected: TimetableTextError) {
        #expect(throws: expected) {
            try TimetableTextParser.parse(header + body)
        }
    }

    @Test func reportsMissingAndInvalidHeader() {
        #expect(throws: TimetableTextError.missingKey("station")) {
            try TimetableTextParser.parse("line: l 線\ndirection: d 方面\nvalidFrom: 2026-03-14\n[weekday]\n[holiday]\n")
        }
        #expect(throws: TimetableTextError.invalidValue(line: 1, key: "station", value: "駅名だけ")) {
            try TimetableTextParser.parse("station: 駅名だけ\nline: l 線\ndirection: d 方面\nvalidFrom: 2026-03-14\n[weekday]\n[holiday]\n")
        }
        #expect(throws: TimetableTextError.invalidValue(line: 4, key: "validFrom", value: "2026-02-30")) {
            try TimetableTextParser.parse("station: s 駅\nline: l 線\ndirection: d 方面\nvalidFrom: 2026-02-30\n[weekday]\n[holiday]\n")
        }
    }
}
