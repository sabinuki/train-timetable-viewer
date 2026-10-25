import Foundation

/// 祝日の一覧
public struct HolidayCalendar: Sendable, Equatable {
    /// 祝日と、その名称
    public let names: [CalendarDate: String]

    public init(names: [CalendarDate: String]) {
        self.names = names
    }

    public func isHoliday(_ date: CalendarDate) -> Bool {
        names[date] != nil
    }

    public func name(of date: CalendarDate) -> String? {
        names[date]
    }

    /// 収録されている最後の祝日
    public var lastDate: CalendarDate? {
        names.keys.max()
    }
}

public enum HolidayRepositoryError: Error, Equatable, LocalizedError {
    case unreadableEncoding
    case invalidRow(line: Int, text: String)
    case empty

    public var errorDescription: String? {
        switch self {
        case .unreadableEncoding:
            "祝日 CSV の文字コードを読み取れません"
        case .invalidRow(let line, let text):
            "祝日 CSV の \(line) 行目を読み取れません: \(text)"
        case .empty:
            "祝日 CSV に祝日がありません"
        }
    }
}

/// 内閣府「国民の祝日」CSV の読み込み（設計書 §4.1）
public enum HolidayRepository {
    /// パッケージに同梱した CSV
    public static func loadBundled() throws -> HolidayCalendar {
        guard let url = Bundle.module.url(forResource: "syukujitsu", withExtension: "csv") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try parse(csv: Data(contentsOf: url))
    }

    /// `1955/1/1,元日` 形式の CSV を読み込む。1 行目の見出しは読み飛ばす。
    /// 内閣府の配布形式（Shift_JIS）と UTF-8 のどちらにも対応する
    public static func parse(csv data: Data) throws -> HolidayCalendar {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
            throw HolidayRepositoryError.unreadableEncoding
        }

        var names: [CalendarDate: String] = [:]
        let lines = text.split(whereSeparator: \.isNewline)
        for (index, rawLine) in lines.enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let columns = line.split(separator: ",", maxSplits: 1).map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            guard let dateText = columns.first, let date = parseDate(dateText) else {
                if index == 0 { continue }  // 見出し行
                throw HolidayRepositoryError.invalidRow(line: index + 1, text: line)
            }
            names[date] = columns.count > 1 ? columns[1] : ""
        }
        guard !names.isEmpty else { throw HolidayRepositoryError.empty }
        return HolidayCalendar(names: names)
    }

    /// `yyyy/M/d`（月日はゼロ埋めなしも可）
    private static func parseDate(_ text: String) -> CalendarDate? {
        let parts = text.split(separator: "/")
        guard parts.count == 3, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else {
            return nil
        }
        return CalendarDate(string: String(format: "%04d-%02d-%02d", year, month, day))
    }
}
