import Foundation

/// `UserDefaults` に保存する設定値
public struct AppSettings {
    public let defaults: UserDefaults

    public static let minutesToStationRange = 0...120
    public static let defaultDisplayCount = 5
    public static let panelOpacityRange = 0.3...1.0

    private enum Key {
        static let minutesToStation = "minutesToStation"
        static let selectedRouteKey = "selectedRouteKey"
        static let isPanelVisible = "isPanelVisible"
        static let panelOpacity = "panelOpacity"
        static let isClickThrough = "isClickThrough"
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

    /// フローティングパネルを表示しているか。初期値は表示
    public var isPanelVisible: Bool {
        get { defaults.object(forKey: Key.isPanelVisible) as? Bool ?? true }
        nonmutating set { defaults.set(newValue, forKey: Key.isPanelVisible) }
    }

    /// パネルの不透明度（0.3〜1.0）。初期値は 1.0
    public var panelOpacity: Double {
        get {
            let value = defaults.object(forKey: Key.panelOpacity) as? Double ?? 1.0
            return min(max(value, Self.panelOpacityRange.lowerBound), Self.panelOpacityRange.upperBound)
        }
        nonmutating set {
            let clamped = min(max(newValue, Self.panelOpacityRange.lowerBound), Self.panelOpacityRange.upperBound)
            defaults.set(clamped, forKey: Key.panelOpacity)
        }
    }

    /// パネルへのクリックを下のウィンドウに素通しするか。初期値はオフ
    public var isClickThrough: Bool {
        get { defaults.bool(forKey: Key.isClickThrough) }
        nonmutating set { defaults.set(newValue, forKey: Key.isClickThrough) }
    }

    /// パネルに表示する本数。設定画面からの変更は #20 で追加する
    public var displayCount: Int {
        Self.defaultDisplayCount
    }

    static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, minutesToStationRange.lowerBound), minutesToStationRange.upperBound)
    }
}
