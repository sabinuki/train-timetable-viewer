import Foundation

/// `UserDefaults` に保存する設定値
public struct AppSettings {
    public let defaults: UserDefaults

    public static let minutesToStationRange = 0...120
    public static let defaultDisplayCount = 5

    private enum Key {
        static let minutesToStation = "minutesToStation"
        static let selectedRouteKey = "selectedRouteKey"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 駅までの所要時間（分）。初期値は 0
    public var minutesToStation: Int {
        get { Self.clamp(defaults.integer(forKey: Key.minutesToStation)) }
        nonmutating set { defaults.set(Self.clamp(newValue), forKey: Key.minutesToStation) }
    }

    /// 表示中の駅・路線・方面（`Timetable.routeKey`）
    public var selectedRouteKey: String? {
        get { defaults.string(forKey: Key.selectedRouteKey) }
        nonmutating set { defaults.set(newValue, forKey: Key.selectedRouteKey) }
    }

    /// パネルに表示する本数。設定画面からの変更は #20 で追加する
    public var displayCount: Int {
        Self.defaultDisplayCount
    }

    static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, minutesToStationRange.lowerBound), minutesToStationRange.upperBound)
    }
}
