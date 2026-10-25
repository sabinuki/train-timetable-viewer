import Foundation

public struct Station: Codable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Line: Codable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Direction: Codable, Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// ダイヤの区分
public enum CalendarKind: String, Codable, CaseIterable, Sendable {
    case weekday
    case saturday
    case holiday

    public var displayName: String {
        switch self {
        case .weekday: "平日"
        case .saturday: "土曜"
        case .holiday: "土休日"
        }
    }
}

/// 時刻表データの取得元
public enum TimetableSource: String, Codable, Sendable {
    case manual
    case odpt
}

/// 1 本の発車
public struct Departure: Hashable, Sendable {
    public let time: ServiceTime
    /// 種別（例: 快速）
    public let type: String?
    /// 行き先
    public let destination: String?

    public init(time: ServiceTime, type: String? = nil, destination: String? = nil) {
        self.time = time
        self.type = type
        self.destination = destination
    }
}

extension Departure: Codable {
    private enum CodingKeys: String, CodingKey {
        case time, type, destination
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .time)
        guard let time = ServiceTime(string: text) else {
            throw TimetableError.invalidTime(text)
        }
        self.init(
            time: time,
            type: try container.decodeIfPresent(String.self, forKey: .type),
            destination: try container.decodeIfPresent(String.self, forKey: .destination))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(time.description, forKey: .time)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(destination, forKey: .destination)
    }
}

/// 1 つの駅・路線・方面の時刻表（設計書 §8.1）
public struct Timetable: Hashable, Sendable {
    public static let currentVersion = 1

    public let station: Station
    public let line: Line
    public let direction: Direction
    /// ダイヤ改正日。この日以降の運行日に有効
    public let validFrom: CalendarDate
    public let source: TimetableSource
    /// ダイヤ区分ごとの発車（時刻の昇順）。`saturday` は省略できる
    public let calendars: [CalendarKind: [Departure]]

    public init(
        station: Station,
        line: Line,
        direction: Direction,
        validFrom: CalendarDate,
        source: TimetableSource = .manual,
        calendars: [CalendarKind: [Departure]]
    ) {
        self.station = station
        self.line = line
        self.direction = direction
        self.validFrom = validFrom
        self.source = source
        self.calendars = calendars.mapValues { $0.sorted { $0.time < $1.time } }
    }

    /// 同じ駅・路線・方面かを判定するためのキー
    public var routeKey: String {
        "\(station.id)/\(line.id)/\(direction.id)"
    }

    /// 土曜ダイヤを持つか
    public var hasSaturdayCalendar: Bool {
        calendars[.saturday] != nil
    }

    /// 指定した区分の発車。区分がなければ空
    public func departures(for kind: CalendarKind) -> [Departure] {
        calendars[kind] ?? []
    }

    /// `candidates` のうち、`date` に有効な時刻表（`validFrom` が `date` 以前で最も新しいもの）
    public static func effective(among candidates: [Timetable], on date: CalendarDate) -> Timetable? {
        candidates
            .filter { $0.validFrom <= date }
            .max { $0.validFrom < $1.validFrom }
    }
}

extension Timetable: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, station, line, direction, validFrom, source, calendars
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw TimetableError.unsupportedVersion(version)
        }

        let rawCalendars = try container.decode([String: [Departure]].self, forKey: .calendars)
        var calendars: [CalendarKind: [Departure]] = [:]
        for (key, departures) in rawCalendars {
            guard let kind = CalendarKind(rawValue: key) else {
                throw TimetableError.unknownCalendar(key)
            }
            calendars[kind] = departures
        }
        for required in [CalendarKind.weekday, .holiday] where calendars[required] == nil {
            throw TimetableError.missingCalendar(required)
        }

        self.init(
            station: try container.decode(Station.self, forKey: .station),
            line: try container.decode(Line.self, forKey: .line),
            direction: try container.decode(Direction.self, forKey: .direction),
            validFrom: try container.decode(CalendarDate.self, forKey: .validFrom),
            source: try container.decodeIfPresent(TimetableSource.self, forKey: .source) ?? .manual,
            calendars: calendars)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(station, forKey: .station)
        try container.encode(line, forKey: .line)
        try container.encode(direction, forKey: .direction)
        try container.encode(validFrom, forKey: .validFrom)
        try container.encode(source, forKey: .source)
        let rawCalendars = Dictionary(uniqueKeysWithValues: calendars.map { ($0.key.rawValue, $0.value) })
        try container.encode(rawCalendars, forKey: .calendars)
    }

    /// JSON から読み込む。形式の誤りは `TimetableError` として返す
    public static func decode(from data: Data) throws -> Timetable {
        do {
            return try JSONDecoder().decode(Timetable.self, from: data)
        } catch let error as TimetableError {
            throw error
        } catch {
            throw TimetableError.malformed(String(describing: error))
        }
    }

    /// 人が読みやすい形式の JSON に書き出す
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// 時刻表データの誤り
public enum TimetableError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)
    case invalidTime(String)
    case unknownCalendar(String)
    case missingCalendar(CalendarKind)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "対応していない時刻表の形式です（version: \(version)）"
        case .invalidTime(let text):
            "時刻は HH:mm 形式（時は 0〜\(ServiceTime.maxHour)）で指定してください: \(text)"
        case .unknownCalendar(let key):
            "不明なダイヤ区分です: \(key)（weekday、saturday、holiday のいずれか）"
        case .missingCalendar(let kind):
            "\(kind.displayName)ダイヤ（\(kind.rawValue)）がありません"
        case .malformed(let detail):
            "時刻表の JSON を読み込めません: \(detail)"
        }
    }
}
