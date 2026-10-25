import Foundation

/// タイムゾーンに依存しない暦日（年月日）。JSON では `yyyy-MM-dd` で表す。
public struct CalendarDate: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// `date` を `calendar`（のタイムゾーン）で見たときの暦日
    public init(_ date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year!, month: components.month!, day: components.day!)
    }

    /// `yyyy-MM-dd` 形式の文字列から作る。実在しない日付は `nil`
    public init?(string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else { return nil }
        let candidate = CalendarDate(year: year, month: month, day: day)
        guard candidate.isValid else { return nil }
        self = candidate
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: CalendarDate, rhs: CalendarDate) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// その日の 0:00（`calendar` のタイムゾーン）
    public func startDate(in calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    /// `days` 日後の暦日
    public func adding(days: Int) -> CalendarDate {
        let calendar = Self.gregorianUTC
        let date = calendar.date(byAdding: .day, value: days, to: startDate(in: calendar))!
        return CalendarDate(date, calendar: calendar)
    }

    /// 曜日（1 = 日曜 … 7 = 土曜。`Calendar` の `weekday` と同じ）
    public var weekday: Int {
        let calendar = Self.gregorianUTC
        return calendar.component(.weekday, from: startDate(in: calendar))
    }

    private var isValid: Bool {
        let calendar = Self.gregorianUTC
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            return false
        }
        return CalendarDate(date, calendar: calendar) == self
    }

    private static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
}

extension CalendarDate: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let date = CalendarDate(string: string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "日付は yyyy-MM-dd 形式で指定してください: \(string)")
        }
        self = date
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
