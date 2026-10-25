import Foundation

/// 出発すべき時刻の前に出す通知の設定（設計書 §9.4）
public struct NotificationSettings: Codable, Hashable, Sendable {
    public var isEnabled: Bool
    /// 出発すべき時刻の何分前に通知するか
    public var minutesBefore: Int
    /// 通知する時間帯（0:00 からの分）。`windowStart > windowEnd` なら日付をまたぐ（例: 22:00〜1:00）
    public var windowStart: Int
    public var windowEnd: Int

    public static let minutesBeforeRange = 0...60

    public init(isEnabled: Bool = false, minutesBefore: Int = 5, windowStart: Int = 17 * 60, windowEnd: Int = 20 * 60) {
        self.isEnabled = isEnabled
        self.minutesBefore = minutesBefore
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }

    /// 0:00 からの分 `minuteOfDay` が通知する時間帯に入るか
    public func isInWindow(minuteOfDay: Int) -> Bool {
        if windowStart == windowEnd { return true }
        if windowStart < windowEnd {
            return (windowStart..<windowEnd).contains(minuteOfDay)
        }
        return minuteOfDay >= windowStart || minuteOfDay < windowEnd
    }
}

/// ユースケース（職場から帰る、自宅から出かけるなど）ごとの設定（設計書 §1.1、F-11）
public struct RouteProfile: Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// 表示する駅・路線・方面（`Timetable.routeKey`）。時刻表を取り込む前は `nil`
    public var routeKey: String?
    /// 駅までの所要時間（分）
    public var minutesToStation: Int
    public var notification: NotificationSettings

    public init(
        id: UUID = UUID(),
        name: String,
        routeKey: String?,
        minutesToStation: Int = 0,
        notification: NotificationSettings = NotificationSettings()
    ) {
        self.id = id
        self.name = name
        self.routeKey = routeKey
        self.minutesToStation = AppSettings.clamp(minutesToStation)
        self.notification = notification
    }

    /// 時刻表から付ける既定の名前（例: `〇〇駅 ××方面`）
    public static func defaultName(for timetable: Timetable?) -> String {
        guard let timetable else { return "プロファイル" }
        return "\(timetable.station.name) \(timetable.direction.name)"
    }
}

extension RouteProfile: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, routeKey, minutesToStation, notification
    }

    /// 後から追加した項目（通知など）がない保存値も読めるようにする
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            name: try container.decode(String.self, forKey: .name),
            routeKey: try container.decodeIfPresent(String.self, forKey: .routeKey),
            minutesToStation: try container.decodeIfPresent(Int.self, forKey: .minutesToStation) ?? 0,
            notification: try container.decodeIfPresent(NotificationSettings.self, forKey: .notification)
                ?? NotificationSettings())
    }
}
