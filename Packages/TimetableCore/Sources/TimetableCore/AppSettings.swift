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
        static let profiles = "profiles"
        static let selectedProfileID = "selectedProfileID"
        static let isPanelVisible = "isPanelVisible"
        static let panelOpacity = "panelOpacity"
        static let isClickThrough = "isClickThrough"
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 路線プロファイル。保存されていなければ `nil`
    public var profiles: [RouteProfile]? {
        get {
            guard let data = defaults.data(forKey: Key.profiles) else { return nil }
            return try? JSONDecoder().decode([RouteProfile].self, from: data)
        }
        nonmutating set {
            defaults.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: Key.profiles)
        }
    }

    /// 表示中の路線プロファイル
    public var selectedProfileID: UUID? {
        get { defaults.string(forKey: Key.selectedProfileID).flatMap(UUID.init(uuidString:)) }
        nonmutating set { defaults.set(newValue?.uuidString, forKey: Key.selectedProfileID) }
    }

    /// 路線プロファイル導入前（#19 より前）の駅までの所要時間。移行にだけ使う
    var legacyMinutesToStation: Int? {
        defaults.object(forKey: Key.minutesToStation) == nil ? nil : Self.clamp(defaults.integer(forKey: Key.minutesToStation))
    }

    /// 路線プロファイル導入前の表示中の駅・路線・方面。移行にだけ使う
    var legacySelectedRouteKey: String? {
        defaults.string(forKey: Key.selectedRouteKey)
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

    public static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, minutesToStationRange.lowerBound), minutesToStationRange.upperBound)
    }
}
