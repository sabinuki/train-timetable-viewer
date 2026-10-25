import Foundation
import Testing
@testable import TimetableCore

private func day(_ text: String) -> CalendarDate {
    CalendarDate(string: text)!
}

/// 日本時間の日時
func tokyoDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int = 0) -> Date {
    ServiceDayResolver.japaneseCalendar.date(
        from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

@Suite struct HolidayRepositoryTests {
    @Test func loadsBundledCSV() throws {
        let holidays = try HolidayRepository.loadBundled()
        #expect(holidays.name(of: day("2026-01-01")) == "元日")
        #expect(holidays.name(of: day("2026-05-06")) == "休日")  // 振替休日
        #expect(holidays.name(of: day("2026-09-22")) == "休日")  // 国民の休日
        #expect(!holidays.isHoliday(day("2026-10-26")))
        #expect(try #require(holidays.lastDate) >= day("2026-12-31").adding(days: -60))
    }

    @Test func parsesShiftJISAndUTF8() throws {
        let csv = "国民の祝日・休日月日,国民の祝日・休日名称\r\n2026/1/1,元日\r\n2026/11/03,文化の日\r\n"
        for encoding in [String.Encoding.shiftJIS, .utf8] {
            let holidays = try HolidayRepository.parse(csv: try #require(csv.data(using: encoding)))
            #expect(holidays.names == [day("2026-01-01"): "元日", day("2026-11-03"): "文化の日"])
        }
    }

    @Test func rejectsInvalidRows() {
        #expect(throws: HolidayRepositoryError.invalidRow(line: 3, text: "2026/13/1,不正")) {
            try HolidayRepository.parse(csv: Data("見出し,名称\n2026/1/1,元日\n2026/13/1,不正\n".utf8))
        }
        #expect(throws: HolidayRepositoryError.empty) {
            try HolidayRepository.parse(csv: Data("見出し,名称\n".utf8))
        }
    }
}

@Suite struct ServiceDayResolverTests {
    let resolver = ServiceDayResolver(
        holidays: HolidayCalendar(names: [day("2026-11-03"): "文化の日"]),
        additionalHolidays: [day("2026-12-30")])

    @Test func momentDuringTheDay() {
        let moment = resolver.moment(at: tokyoDate(2026, 10, 26, 18, 5, 59))
        #expect(moment == ServiceMoment(serviceDay: day("2026-10-26"), time: ServiceTime(hour: 18, minute: 5)))
    }

    @Test func momentBeforeBoundaryBelongsToPreviousServiceDay() {
        let moment = resolver.moment(at: tokyoDate(2026, 10, 27, 0, 30))
        #expect(moment == ServiceMoment(serviceDay: day("2026-10-26"), time: ServiceTime(hour: 24, minute: 30)))
        #expect(resolver.moment(at: tokyoDate(2026, 10, 27, 2, 59)).time == ServiceTime(hour: 26, minute: 59))
    }

    @Test func momentAtBoundaryBelongsToNewServiceDay() {
        let moment = resolver.moment(at: tokyoDate(2026, 10, 27, 3, 0))
        #expect(moment == ServiceMoment(serviceDay: day("2026-10-27"), time: ServiceTime(hour: 3, minute: 0)))
    }

    @Test func momentAcrossMonthEnd() {
        let moment = resolver.moment(at: tokyoDate(2026, 11, 1, 1, 0))
        #expect(moment.serviceDay == day("2026-10-31"))
    }

    @Test func momentUsesTokyoTimeRegardlessOfSystemZone() {
        // UTC 15:30 は日本時間 0:30（翌日）
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let date = utc.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 15, minute: 30))!
        #expect(resolver.moment(at: date) == ServiceMoment(serviceDay: day("2026-10-26"), time: ServiceTime(hour: 24, minute: 30)))
    }

    @Test func dateForServiceTimeAfterMidnight() {
        let date = resolver.date(serviceDay: day("2026-10-26"), time: ServiceTime(hour: 24, minute: 21))
        #expect(date == tokyoDate(2026, 10, 27, 0, 21))
    }

    @Test func weekdayCalendar() {
        #expect(resolver.calendarKind(for: day("2026-10-26"), hasSaturdayCalendar: true) == .weekday)  // 月曜
        #expect(resolver.calendarKind(for: day("2026-10-30"), hasSaturdayCalendar: false) == .weekday)  // 金曜
    }

    @Test func sundayIsHoliday() {
        #expect(resolver.calendarKind(for: day("2026-10-25"), hasSaturdayCalendar: true) == .holiday)
    }

    @Test func saturdayUsesSaturdayCalendarOnlyWhenAvailable() {
        #expect(resolver.calendarKind(for: day("2026-10-31"), hasSaturdayCalendar: true) == .saturday)
        #expect(resolver.calendarKind(for: day("2026-10-31"), hasSaturdayCalendar: false) == .holiday)
    }

    @Test func nationalHolidayIsHoliday() {
        #expect(resolver.calendarKind(for: day("2026-11-03"), hasSaturdayCalendar: true) == .holiday)  // 火曜の祝日
    }

    @Test func additionalHolidayIsHoliday() {
        #expect(resolver.calendarKind(for: day("2026-12-30"), hasSaturdayCalendar: false) == .holiday)  // 水曜
        #expect(resolver.calendarKind(for: day("2026-12-29"), hasSaturdayCalendar: false) == .weekday)
    }

    @Test func substituteHolidayFromBundledData() throws {
        let resolver = ServiceDayResolver(holidays: try HolidayRepository.loadBundled())
        #expect(resolver.calendarKind(for: day("2026-05-06"), hasSaturdayCalendar: false) == .holiday)  // 振替休日（水曜）
        #expect(resolver.calendarKind(for: day("2026-05-07"), hasSaturdayCalendar: false) == .weekday)
    }

    @Test func earlyMorningAfterHolidayUsesHolidayCalendar() {
        // 祝日の翌日 0:30 は、祝日の運行日として土休日ダイヤ
        let moment = resolver.moment(at: tokyoDate(2026, 11, 4, 0, 30))
        #expect(resolver.calendarKind(for: moment.serviceDay, hasSaturdayCalendar: false) == .holiday)
    }
}
