import Foundation

/// `UserDefaults` に保存する設定値
public struct AppSettings {
    public let defaults: UserDefaults

    public static let minutesToStationRange = 0...120
    public static let defaultDisplayCount = 5
    public static let panelOpacityRange = 0.3...1.0
    public static let displayCountRange = 3...10

    private enum Key {
        static let minutesToStation = "minutesToStation"
        static let selectedRouteKey = "selectedRouteKey"
        static let profiles = "profiles"
        static let selectedProfileID = "selectedProfileID"
        static let isPanelVisible = "isPanelVisible"
        static let panelOpacity = "panelOpacity"
        static let isClickThrough = "isClickThrough"
        static let displayCount = "displayCount"
        static let menuBarStyle = "menuBarStyle"
        static let showsSeconds = "showsSeconds"
        static let additionalHolidays = "additionalHolidays"
        static let hotKey = "hotKey"
        static let holidaysLastFetched = "holidaysLastFetched"
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

    /// パネルに表示する本数（3〜10）
    public var displayCount: Int {
        get {
            let value = defaults.object(forKey: Key.displayCount) as? Int ?? Self.defaultDisplayCount
            return min(max(value, Self.displayCountRange.lowerBound), Self.displayCountRange.upperBound)
        }
        nonmutating set {
            defaults.set(min(max(newValue, Self.displayCountRange.lowerBound), Self.displayCountRange.upperBound), forKey: Key.displayCount)
        }
    }

    /// メニューバーの表示形式
    public var menuBarStyle: MenuBarStyle {
        get { defaults.string(forKey: Key.menuBarStyle).flatMap(MenuBarStyle.init(rawValue:)) ?? .nextDeparture }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.menuBarStyle) }
    }

    /// 残り時間を秒単位で表示するか
    public var showsSeconds: Bool {
        get { defaults.bool(forKey: Key.showsSeconds) }
        nonmutating set { defaults.set(newValue, forKey: Key.showsSeconds) }
    }

    /// 土休日ダイヤとして扱う追加の日（年末年始など）
    public var additionalHolidays: Set<CalendarDate> {
        get { Set((defaults.stringArray(forKey: Key.additionalHolidays) ?? []).compactMap(CalendarDate.init(string:))) }
        nonmutating set { defaults.set(newValue.sorted().map(\.description), forKey: Key.additionalHolidays) }
    }

    /// 祝日データを最後に取得できた日時
    public var holidaysLastFetched: Date? {
        get { defaults.object(forKey: Key.holidaysLastFetched) as? Date }
        nonmutating set { defaults.set(newValue, forKey: Key.holidaysLastFetched) }
    }

    /// パネルの表示を切り替えるグローバルショートカット
    public var hotKey: HotKeySetting {
        get {
            guard let data = defaults.data(forKey: Key.hotKey),
                  let setting = try? JSONDecoder().decode(HotKeySetting.self, from: data)
            else { return .default }
            return setting
        }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.hotKey) }
    }

    public static func clamp(_ minutes: Int) -> Int {
        min(max(minutes, minutesToStationRange.lowerBound), minutesToStationRange.upperBound)
    }
}

/// メニューバーの表示形式（設計書 §6.1）
public enum MenuBarStyle: String, CaseIterable, Sendable {
    /// 次発の時刻と残り時間（例: `18:05 あと12分`）
    case nextDeparture
    /// 出発すべき時刻と残り時間（例: `17:57 出発 あと4分`）
    case leaveBy
    /// アイコンのみ
    case iconOnly

    public var displayName: String {
        switch self {
        case .nextDeparture: "次発の時刻"
        case .leaveBy: "出発すべき時刻"
        case .iconOnly: "アイコンのみ"
        }
    }
}

/// グローバルショートカットのキーの組み合わせ。値は Carbon の仮想キーコードと修飾キー
public struct HotKeySetting: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var carbonModifiers: UInt32
    /// 表示用（例: `⌥⌘T`）
    public var label: String

    public init(keyCode: UInt32, carbonModifiers: UInt32, label: String) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
        self.label = label
    }

    /// ⌥⌘T（kVK_ANSI_T = 0x11、optionKey | cmdKey = 0x0800 | 0x0100）
    public static let `default` = HotKeySetting(keyCode: 0x11, carbonModifiers: 0x0900, label: "⌥⌘T")
}
