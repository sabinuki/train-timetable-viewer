import Foundation

/// ユースケース（職場から帰る、自宅から出かけるなど）ごとの設定（設計書 §1.1、F-11）
public struct RouteProfile: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// 表示する駅・路線・方面（`Timetable.routeKey`）。時刻表を取り込む前は `nil`
    public var routeKey: String?
    /// 駅までの所要時間（分）
    public var minutesToStation: Int

    public init(id: UUID = UUID(), name: String, routeKey: String?, minutesToStation: Int = 0) {
        self.id = id
        self.name = name
        self.routeKey = routeKey
        self.minutesToStation = AppSettings.clamp(minutesToStation)
    }

    /// 時刻表から付ける既定の名前（例: `〇〇駅 ××方面`）
    public static func defaultName(for timetable: Timetable?) -> String {
        guard let timetable else { return "プロファイル" }
        return "\(timetable.station.name) \(timetable.direction.name)"
    }
}
