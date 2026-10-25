import Foundation


/// 手入力しやすいテキスト形式の時刻表を `Timetable` に変換する。
///
/// ```
/// station: example-station 〇〇駅
/// line: example-line △△線
/// direction: outbound ××方面
/// validFrom: 2026-03-14
/// type: 快=快速, 特=特急
/// type-default: 各停
/// destination: □=□□
/// destination-default: ××
///
/// [weekday]
/// 18: 05快 12 20快□ 31
/// 24: 21□
/// ```
///
/// - `HH: mm mm …` の各分の後ろに付けた 1 文字の記号を、`type` と `destination` の略記として展開する
/// - 記号のない発車には `type-default` と `destination-default` を使う
/// - `#` 以降はコメント
public enum TimetableTextParser {
    public static func parse(_ text: String) throws(TimetableTextError) -> Timetable {
        var header: [String: (value: String, line: Int)] = [:]
        var typeMarks: [Character: String] = [:]
        var destinationMarks: [Character: String] = [:]
        var calendars: [CalendarKind: [Departure]] = [:]
        var rows: [(kind: CalendarKind, hour: Int, tokens: [Substring], line: Int)] = []
        var currentKind: CalendarKind?

        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let lineNumber = index + 1
            let line = rawLine.prefix { $0 != "#" }.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }

            if line.hasPrefix("[") {
                guard line.hasSuffix("]"), let kind = CalendarKind(rawValue: String(line.dropFirst().dropLast())) else {
                    throw .invalidSection(line: lineNumber, text: line)
                }
                guard calendars[kind] == nil else { throw .duplicateSection(line: lineNumber, kind: kind) }
                calendars[kind] = []
                currentKind = kind
                continue
            }

            guard let colon = line.firstIndex(of: ":") else {
                throw .invalidLine(line: lineNumber, text: line)
            }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)

            if let hour = Int(key), key.allSatisfy(\.isASCII) {
                guard let kind = currentKind else { throw .departureOutsideSection(line: lineNumber) }
                guard (0...ServiceTime.maxHour).contains(hour) else { throw .invalidTime(line: lineNumber, text: key) }
                rows.append((kind, hour, value.split(whereSeparator: \.isWhitespace), lineNumber))
                continue
            }

            guard currentKind == nil else { throw .headerInsideSection(line: lineNumber, key: key) }
            switch key {
            case "type":
                typeMarks.merge(try parseMarks(value, line: lineNumber)) { $1 }
            case "destination":
                destinationMarks.merge(try parseMarks(value, line: lineNumber)) { $1 }
            case "station", "line", "direction", "validFrom", "type-default", "destination-default", "source":
                header[key] = (value, lineNumber)
            default:
                throw .unknownKey(line: lineNumber, key: key)
            }
        }

        let defaultType = header["type-default"]?.value
        let defaultDestination = header["destination-default"]?.value
        for row in rows {
            for token in row.tokens {
                let digits = token.prefix(while: \.isASCII).prefix(while: \.isNumber)
                guard digits.count == 2 || digits.count == 1, let minute = Int(digits), (0...59).contains(minute) else {
                    throw .invalidTime(line: row.line, text: String(token))
                }
                var type = defaultType
                var destination = defaultDestination
                for mark in token.dropFirst(digits.count) {
                    if let expanded = typeMarks[mark] {
                        type = expanded
                    } else if let expanded = destinationMarks[mark] {
                        destination = expanded
                    } else {
                        throw .unknownMark(line: row.line, mark: mark)
                    }
                }
                calendars[row.kind, default: []].append(
                    Departure(time: ServiceTime(hour: row.hour, minute: minute), type: type, destination: destination))
            }
        }

        for required in [CalendarKind.weekday, .holiday] where calendars[required] == nil {
            throw .missingSection(required)
        }

        let source: TimetableSource
        if let raw = header["source"] {
            guard let parsed = TimetableSource(rawValue: raw.value) else {
                throw .invalidValue(line: raw.line, key: "source", value: raw.value)
            }
            source = parsed
        } else {
            source = .manual
        }

        return Timetable(
            station: try identified(header, "station", Station.init),
            line: try identified(header, "line", Line.init),
            direction: try identified(header, "direction", Direction.init),
            validFrom: try validFrom(header),
            source: source,
            calendars: calendars)
    }

    /// `快=快速, 特=特急`
    private static func parseMarks(_ value: String, line: Int) throws(TimetableTextError) -> [Character: String] {
        var marks: [Character: String] = [:]
        for pair in value.split(separator: ",") {
            let parts = pair.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0].count == 1, let mark = parts[0].first,
                  !mark.isNumber, !mark.isWhitespace, !parts[1].isEmpty
            else {
                throw .invalidValue(line: line, key: "mark", value: String(pair))
            }
            marks[mark] = parts[1]
        }
        return marks
    }

    /// `<id> <名前>`
    private static func identified<T>(
        _ header: [String: (value: String, line: Int)],
        _ key: String,
        _ make: (String, String) -> T
    ) throws(TimetableTextError) -> T {
        guard let entry = header[key] else { throw .missingKey(key) }
        let parts = entry.value.split(separator: " ", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, !parts[1].isEmpty else {
            throw .invalidValue(line: entry.line, key: key, value: entry.value)
        }
        return make(parts[0], parts[1])
    }

    private static func validFrom(_ header: [String: (value: String, line: Int)]) throws(TimetableTextError) -> CalendarDate {
        guard let entry = header["validFrom"] else { throw .missingKey("validFrom") }
        guard let date = CalendarDate(string: entry.value) else {
            throw .invalidValue(line: entry.line, key: "validFrom", value: entry.value)
        }
        return date
    }
}

public enum TimetableTextError: Error, Equatable, CustomStringConvertible {
    case invalidLine(line: Int, text: String)
    case invalidSection(line: Int, text: String)
    case duplicateSection(line: Int, kind: CalendarKind)
    case missingSection(CalendarKind)
    case departureOutsideSection(line: Int)
    case headerInsideSection(line: Int, key: String)
    case unknownKey(line: Int, key: String)
    case missingKey(String)
    case invalidValue(line: Int, key: String, value: String)
    case invalidTime(line: Int, text: String)
    case unknownMark(line: Int, mark: Character)

    public var description: String {
        switch self {
        case .invalidLine(let line, let text):
            "\(line) 行目: 読み取れない行です: \(text)"
        case .invalidSection(let line, let text):
            "\(line) 行目: 区分は [weekday]、[saturday]、[holiday] のいずれかです: \(text)"
        case .duplicateSection(let line, let kind):
            "\(line) 行目: [\(kind.rawValue)] が重複しています"
        case .missingSection(let kind):
            "[\(kind.rawValue)]（\(kind.displayName)ダイヤ）がありません"
        case .departureOutsideSection(let line):
            "\(line) 行目: 発車時刻の前に [weekday] などの区分を書いてください"
        case .headerInsideSection(let line, let key):
            "\(line) 行目: \(key) は最初の区分より前に書いてください"
        case .unknownKey(let line, let key):
            "\(line) 行目: 不明な項目です: \(key)"
        case .missingKey(let key):
            "\(key) がありません"
        case .invalidValue(let line, let key, let value):
            "\(line) 行目: \(key) の値が不正です: \(value)"
        case .invalidTime(let line, let text):
            "\(line) 行目: 時刻が不正です: \(text)"
        case .unknownMark(let line, let mark):
            "\(line) 行目: 定義されていない記号です: \(mark)（type または destination で定義してください）"
        }
    }
}
