import Foundation
import Testing
@testable import TimetableCore

@Suite struct NotificationSettingsTests {
    @Test func windowWithinDay() {
        let settings = NotificationSettings(windowStart: 17 * 60, windowEnd: 20 * 60)
        #expect(!settings.isInWindow(minuteOfDay: 16 * 60 + 59))
        #expect(settings.isInWindow(minuteOfDay: 17 * 60))
        #expect(settings.isInWindow(minuteOfDay: 19 * 60 + 59))
        #expect(!settings.isInWindow(minuteOfDay: 20 * 60))
    }

    @Test func windowAcrossMidnight() {
        let settings = NotificationSettings(windowStart: 22 * 60, windowEnd: 1 * 60)
        #expect(settings.isInWindow(minuteOfDay: 23 * 60))
        #expect(settings.isInWindow(minuteOfDay: 30))
        #expect(!settings.isInWindow(minuteOfDay: 1 * 60))
        #expect(!settings.isInWindow(minuteOfDay: 12 * 60))
    }

    @Test func sameStartAndEndMeansAllDay() {
        let settings = NotificationSettings(windowStart: 0, windowEnd: 0)
        #expect(settings.isInWindow(minuteOfDay: 3 * 60))
    }

    @Test func decodesProfileSavedBeforeNotificationsExisted() throws {
        let json = #"[{"id":"C992A245-DD47-45E1-B4A9-DD1A63FE09B5","name":"サンプル駅 中央方面","routeKey":"s/l/d","minutesToStation":8}]"#
        let profiles = try JSONDecoder().decode([RouteProfile].self, from: Data(json.utf8))
        #expect(profiles.first?.minutesToStation == 8)
        #expect(profiles.first?.notification == NotificationSettings())
    }

    @Test func roundTripsProfileWithNotification() throws {
        let profile = RouteProfile(
            name: "職場", routeKey: "s/l/d", minutesToStation: 8,
            notification: NotificationSettings(isEnabled: true, minutesBefore: 3, windowStart: 60, windowEnd: 120))
        let decoded = try JSONDecoder().decode(RouteProfile.self, from: JSONEncoder().encode(profile))
        #expect(decoded == profile)
    }
}

@Suite struct NotificationPlannerTests {
    let service = DepartureService(resolver: ServiceDayResolver(holidays: HolidayCalendar(names: [:])))
    let timetable = Timetable(
        station: Station(id: "s", name: "〇〇駅"),
        line: Line(id: "l", name: "△△線"),
        direction: Direction(id: "d", name: "××方面"),
        validFrom: CalendarDate(year: 2026, month: 3, day: 14),
        calendars: [
            .weekday: ["16:50", "17:30", "18:05", "18:12", "18:20", "20:30"].map {
                Departure(time: ServiceTime(string: $0)!, type: "快速", destination: "××")
            },
            .holiday: [],
        ])

    private func profile(enabled: Bool = true, minutesBefore: Int = 5, window: (Int, Int) = (17 * 60, 20 * 60)) -> RouteProfile {
        RouteProfile(
            name: "職場から帰る", routeKey: "s/l/d", minutesToStation: 8,
            notification: NotificationSettings(
                isEnabled: enabled, minutesBefore: minutesBefore, windowStart: window.0, windowEnd: window.1))
    }

    private func plan(at now: Date, _ profile: RouteProfile) -> PlannedNotification? {
        let board = service.board(at: now, timetables: [timetable], minutesToStation: profile.minutesToStation, count: 5)
        return NotificationPlanner.plan(board: board, profile: profile, now: now, calendar: ServiceDayResolver.japaneseCalendar)
    }

    @Test func plansNotificationBeforeLeaveBy() throws {
        // 18:05 発 → 17:57 に出発 → 5 分前の 17:52 に通知
        let planned = try #require(plan(at: tokyoDate(2026, 10, 26, 17, 40), profile()))
        #expect(planned.fireDate == tokyoDate(2026, 10, 26, 17, 52))
        #expect(planned.title == "18:05 発に乗るなら、あと 5 分で出発")
        #expect(planned.body == "17:57 までに出発（職場から帰る・快速 ××行）")
    }

    @Test func skipsDepartureWhoseNotificationTimeHasPassed() throws {
        // 17:53 では 18:05 発の通知時刻（17:52）を過ぎているので、18:12 発（17:59 に通知）にする
        let planned = try #require(plan(at: tokyoDate(2026, 10, 26, 17, 53), profile()))
        #expect(planned.fireDate == tokyoDate(2026, 10, 26, 17, 59))
        #expect(planned.title.hasPrefix("18:12"))
    }

    @Test func respectsTimeWindow() throws {
        // 16:50 発の通知時刻（16:37）は時間帯（17:00〜20:00）の外なので、17:30 発（17:17 に通知）にする
        let planned = try #require(plan(at: tokyoDate(2026, 10, 26, 16, 0), profile()))
        #expect(planned.fireDate == tokyoDate(2026, 10, 26, 17, 17))
        // 20:30 発の通知時刻（20:17）は時間帯の外なので、翌日の 17:30 発（翌日 17:17 に通知）にする
        let nextDay = try #require(plan(at: tokyoDate(2026, 10, 26, 18, 30), profile()))
        #expect(nextDay.fireDate == tokyoDate(2026, 10, 27, 17, 17))
        // 時間帯に入る発車が表示範囲にない
        #expect(plan(at: tokyoDate(2026, 10, 26, 18, 30), profile(window: (9 * 60, 10 * 60))) == nil)
    }

    @Test func zeroMinutesBefore() throws {
        let planned = try #require(plan(at: tokyoDate(2026, 10, 26, 17, 40), profile(minutesBefore: 0)))
        #expect(planned.fireDate == tokyoDate(2026, 10, 26, 17, 57))
        #expect(planned.title == "18:05 発に乗るなら、今出発しましょう")
    }

    @Test func disabledOrMissingProfilePlansNothing() {
        #expect(plan(at: tokyoDate(2026, 10, 26, 17, 40), profile(enabled: false)) == nil)
        #expect(NotificationPlanner.plan(board: nil, profile: profile(), now: Date(), calendar: .current) == nil)
    }

    @Test func samePlanForRepeatedRefreshes() {
        // 再計算しても同じ発車なら同じ内容になり、登録し直す必要がない
        #expect(plan(at: tokyoDate(2026, 10, 26, 17, 40), profile()) == plan(at: tokyoDate(2026, 10, 26, 17, 41), profile()))
    }
}
