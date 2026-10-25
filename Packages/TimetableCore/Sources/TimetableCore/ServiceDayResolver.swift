import Foundation

/// ある時点を、運行日と運行日基準の時刻で表したもの
public struct ServiceMoment: Hashable, Sendable {
    public let serviceDay: CalendarDate
    public let time: ServiceTime

    public init(serviceDay: CalendarDate, time: ServiceTime) {
        self.serviceDay = serviceDay
        self.time = time
    }
}

/// 運行日とダイヤ区分の判定（設計書 §9.1）
public struct ServiceDayResolver: Sendable {
    /// これより前の時刻は前日の運行日として扱う
    public var boundary: ServiceTime
    public var holidays: HolidayCalendar
    /// 土休日ダイヤとして扱う追加の日（年末年始など）
    public var additionalHolidays: Set<CalendarDate>
    /// 時刻表のタイムゾーンを持つ暦
    public var calendar: Calendar

    public static let defaultBoundary = ServiceTime(hour: 3, minute: 0)

    public init(
        boundary: ServiceTime = Self.defaultBoundary,
        holidays: HolidayCalendar,
        additionalHolidays: Set<CalendarDate> = [],
        calendar: Calendar = Self.japaneseCalendar
    ) {
        self.boundary = boundary
        self.holidays = holidays
        self.additionalHolidays = additionalHolidays
        self.calendar = calendar
    }

    /// 日本時間のグレゴリオ暦
    public static let japaneseCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tokyo")!
        return calendar
    }()

    /// `date` の運行日と、運行日基準の時刻（秒は切り捨て）
    public func moment(at date: Date) -> ServiceMoment {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let clock = ServiceTime(hour: components.hour!, minute: components.minute!)
        let day = CalendarDate(date, calendar: calendar)
        if clock < boundary {
            return ServiceMoment(serviceDay: day.adding(days: -1), time: ServiceTime(minutes: clock.minutes + 24 * 60))
        }
        return ServiceMoment(serviceDay: day, time: clock)
    }

    /// 運行日 `serviceDay` の `time` にあたる実際の日時
    public func date(serviceDay: CalendarDate, time: ServiceTime) -> Date {
        calendar.date(byAdding: .minute, value: time.minutes, to: serviceDay.startDate(in: calendar))!
    }

    /// 運行日のダイヤ区分。土曜ダイヤがない時刻表では、土曜を土休日ダイヤとして扱う
    public func calendarKind(for serviceDay: CalendarDate, hasSaturdayCalendar: Bool) -> CalendarKind {
        if additionalHolidays.contains(serviceDay) || holidays.isHoliday(serviceDay) {
            return .holiday
        }
        switch serviceDay.weekday {
        case 1: return .holiday
        case 7: return hasSaturdayCalendar ? .saturday : .holiday
        default: return .weekday
        }
    }
}
