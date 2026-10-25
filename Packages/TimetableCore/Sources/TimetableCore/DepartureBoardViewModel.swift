import Foundation
import Observation

/// メニューバーとパネルが共通で使う表示状態（設計書 §7）
@MainActor
@Observable
public final class DepartureBoardViewModel {
    public enum Status: Equatable, Sendable {
        /// 時刻表が取り込まれていない
        case noTimetable
        /// 取り込んだ時刻表の改正日がまだ来ていない
        case notYetEffective(CalendarDate)
        case ready
    }

    public private(set) var status: Status = .noTimetable
    public private(set) var board: DepartureBoard?
    /// 現在の運行日に有効な時刻表（ヘッダー表示用）
    public private(set) var timetable: Timetable?
    /// 駅・路線・方面ごとの時刻表
    public private(set) var routes: [String: [Timetable]] = [:]

    /// 路線プロファイル（設計書 §1.1）
    public private(set) var profiles: [RouteProfile] = []
    public private(set) var selectedProfileID: UUID?

    public var selectedProfile: RouteProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    /// 表示中の駅・路線・方面
    public var selectedRouteKey: String? {
        selectedProfile?.routeKey
    }

    /// 表示中のプロファイルの、駅までの所要時間（分）。変更すると保存して再計算する
    public var minutesToStation: Int {
        get { selectedProfile?.minutesToStation ?? 0 }
        set {
            guard var profile = selectedProfile else { return }
            profile.minutesToStation = AppSettings.clamp(newValue)
            updateProfile(profile)
        }
    }

    /// パネルに表示する本数（3〜10）
    public var displayCount: Int {
        didSet { saveAndRefresh { $0.displayCount = displayCount } }
    }

    /// メニューバーの表示形式
    public var menuBarStyle: MenuBarStyle {
        didSet { saveAndRefresh { $0.menuBarStyle = menuBarStyle } }
    }

    /// 残り時間を秒単位で表示するか（オンのときは 1 秒ごとに再計算する）
    public var showsSeconds: Bool {
        didSet { saveAndRefresh { $0.showsSeconds = showsSeconds } }
    }

    /// 土休日ダイヤとして扱う追加の日
    public var additionalHolidays: Set<CalendarDate> {
        didSet {
            service.resolver.additionalHolidays = additionalHolidays
            saveAndRefresh { $0.additionalHolidays = additionalHolidays }
        }
    }

    @ObservationIgnored private var service: DepartureService
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date

    public init(service: DepartureService, settings: AppSettings, now: @escaping () -> Date = Date.init) {
        self.service = service
        self.settings = settings
        self.now = now
        self.displayCount = settings.displayCount
        self.menuBarStyle = settings.menuBarStyle
        self.showsSeconds = settings.showsSeconds
        self.additionalHolidays = settings.additionalHolidays
        self.service.resolver.additionalHolidays = settings.additionalHolidays
        self.profiles = settings.profiles ?? []
        self.selectedProfileID = settings.selectedProfileID
    }

    /// 保存済みの時刻表を読み込み直す。プロファイルがなければ作る
    public func load(_ timetables: [Timetable]) {
        routes = Dictionary(grouping: timetables, by: \.routeKey)
        if settings.profiles == nil {
            migrateLegacySettings()
        }
        if profiles.isEmpty, let routeKey = routes.keys.sorted().first {
            profiles = [makeProfile(routeKey: routeKey)]
        }
        if selectedProfile == nil {
            selectedProfileID = profiles.first?.id
        }
        saveProfiles()
        refresh()
    }

    /// 路線プロファイル導入前の単一の設定を、プロファイル 1 件として移行する
    private func migrateLegacySettings() {
        guard profiles.isEmpty else { return }
        let routeKey = settings.legacySelectedRouteKey.flatMap { routes[$0] == nil ? nil : $0 }
            ?? routes.keys.sorted().first
        guard routeKey != nil || settings.legacyMinutesToStation != nil else { return }
        profiles = [makeProfile(routeKey: routeKey, minutesToStation: settings.legacyMinutesToStation ?? 0)]
    }

    // MARK: - 路線プロファイルの操作

    /// 表示するプロファイルを切り替える
    public func selectProfile(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        selectedProfileID = id
        saveProfiles()
        refresh()
    }

    /// 取り込んだ時刻表を表示する。その駅・路線・方面のプロファイルがあれば切り替え、
    /// 表示中のプロファイルに時刻表がなければ割り当て、どちらでもなければ新しいプロファイルを作る
    public func showRoute(_ routeKey: String) {
        guard routes[routeKey] != nil else { return }
        if let existing = profiles.first(where: { $0.routeKey == routeKey }) {
            selectedProfileID = existing.id
        } else if var current = selectedProfile, current.routeKey.map({ routes[$0] == nil }) ?? true {
            current.routeKey = routeKey
            if current.name == RouteProfile.defaultName(for: nil) {
                current.name = RouteProfile.defaultName(for: routes[routeKey]?.first)
            }
            replace(current)
        } else {
            let profile = makeProfile(routeKey: routeKey)
            profiles.append(profile)
            selectedProfileID = profile.id
        }
        saveProfiles()
        refresh()
    }

    /// プロファイルを追加して表示する
    @discardableResult
    public func addProfile(routeKey: String? = nil) -> RouteProfile {
        let profile = makeProfile(routeKey: routeKey ?? selectedRouteKey ?? routes.keys.sorted().first)
        profiles.append(profile)
        selectedProfileID = profile.id
        saveProfiles()
        refresh()
        return profile
    }

    /// プロファイルの名前、時刻表、所要時間などを変更する
    public func updateProfile(_ profile: RouteProfile) {
        guard profiles.contains(where: { $0.id == profile.id }) else { return }
        var profile = profile
        profile.minutesToStation = AppSettings.clamp(profile.minutesToStation)
        replace(profile)
        saveProfiles()
        refresh()
    }

    /// プロファイルを削除する。表示中のプロファイルを削除した場合は先頭のプロファイルを表示する
    public func deleteProfile(_ id: UUID) {
        profiles.removeAll { $0.id == id }
        if selectedProfileID == id {
            selectedProfileID = profiles.first?.id
        }
        saveProfiles()
        refresh()
    }

    private func makeProfile(routeKey: String?, minutesToStation: Int = 0) -> RouteProfile {
        RouteProfile(
            name: RouteProfile.defaultName(for: routeKey.flatMap { routes[$0]?.first }),
            routeKey: routeKey,
            minutesToStation: minutesToStation)
    }

    private func replace(_ profile: RouteProfile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        }
    }

    private func saveAndRefresh(_ save: (AppSettings) -> Void) {
        save(settings)
        refresh()
    }

    private func saveProfiles() {
        settings.profiles = profiles
        settings.selectedProfileID = selectedProfileID
    }

    /// 次に出す通知（表示中のプロファイルで通知がオンのとき）
    public private(set) var plannedNotification: PlannedNotification?

    /// 再計算のたびに呼ばれる（通知の登録し直しなど）
    @ObservationIgnored public var onRefresh: (() -> Void)?

    /// 現在時刻で再計算する
    public func refresh() {
        let date = now()
        recalculate(at: date)
        let planned = NotificationPlanner.plan(
            board: board, profile: selectedProfile, now: date, calendar: service.resolver.calendar)
        if planned != plannedNotification {
            plannedNotification = planned
        }
        onRefresh?()
    }

    private func recalculate(at date: Date) {
        let timetables = selectedRouteKey.flatMap { routes[$0] } ?? []
        guard !timetables.isEmpty else {
            status = .noTimetable
            board = nil
            timetable = nil
            return
        }

        let serviceDay = service.resolver.moment(at: date).serviceDay
        guard let effective = Timetable.effective(among: timetables, on: serviceDay),
              let board = service.board(
                at: date, timetables: timetables, minutesToStation: minutesToStation, count: displayCount,
                filter: selectedProfile?.filter ?? .all)
        else {
            status = .notYetEffective(timetables.map(\.validFrom).min()!)
            board = nil
            timetable = nil
            return
        }
        self.timetable = effective
        self.board = board
        status = .ready
    }

    /// 表示中の路線の時刻表に含まれる種別と行き先（絞り込みの候補）
    public var filterCandidates: (types: [String], destinations: [String]) {
        let departures = (selectedRouteKey.flatMap { routes[$0] } ?? [])
            .flatMap { $0.calendars.values.joined() }
        return (
            Set(departures.compactMap(\.type)).sorted(),
            Set(departures.compactMap(\.destination)).sorted())
    }

    // MARK: - 表示用の文字列

    /// メニューバーに出す次発（乗れる次発。なければ最初の発車）
    public var headlineDeparture: UpcomingDeparture? {
        board?.nextCatchable ?? board?.departures.first
    }

    /// メニューバーの表示（例: `18:05 あと12分`）。アイコンのみの形式では空
    public var menuBarTitle: String {
        switch status {
        case .noTimetable:
            return menuBarStyle == .iconOnly ? "" : "時刻表なし"
        case .notYetEffective(let date):
            return menuBarStyle == .iconOnly ? "" : "\(date.month)/\(date.day) から"
        case .ready:
            guard menuBarStyle != .iconOnly else { return "" }
            guard let board, let departure = headlineDeparture else { return "本日終了" }
            let time = departure.departure.time.clockDescription
            if board.isServiceEnded {
                return "始発 \(time)"
            }
            switch menuBarStyle {
            case .leaveBy where departure.isCatchable:
                return "\(clockText(departure.leaveByDate)) 出発 \(remainingText(until: departure.leaveByDate))"
            default:
                return "\(time) \(remainingText(until: departure.departureDate))"
            }
        }
    }

    /// 発車や出発すべき時刻までの残り時間（例: `あと12分`、秒表示では `あと12分30秒`）
    public func remainingText(until date: Date) -> String {
        let interval = date.timeIntervalSince(board?.now ?? now())
        if showsSeconds {
            let seconds = Int(interval.rounded(.down))
            if seconds < 0 { return "発車済み" }
            if seconds < 60 { return "あと\(seconds)秒" }
            let minutes = seconds / 60
            if minutes >= 60 { return "あと\(minutes / 60)時間\(minutes % 60)分\(seconds % 60)秒" }
            return "あと\(minutes)分\(seconds % 60)秒"
        }
        let minutes = Int((interval / 60).rounded(.down))
        if minutes < 0 { return "発車済み" }
        if minutes == 0 { return "まもなく" }
        if minutes >= 60 { return "あと\(minutes / 60)時間\(minutes % 60)分" }
        return "あと\(minutes)分"
    }

    /// 日時を時刻表のタイムゾーンで `HH:mm` にする
    public func clockText(_ date: Date) -> String {
        let components = service.resolver.calendar.dateComponents([.hour, .minute], from: date)
        return ServiceTime(hour: components.hour!, minute: components.minute!).description
    }
}

/// 次に再計算する時刻（次の分の 0 秒）
public func nextMinuteBoundary(after date: Date) -> Date {
    let seconds = date.timeIntervalSinceReferenceDate
    return Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded(.down) * 60 + 60)
}

/// 秒表示のときに次に再計算する時刻（次の秒の 0 ミリ秒）
public func nextSecondBoundary(after date: Date) -> Date {
    Date(timeIntervalSinceReferenceDate: date.timeIntervalSinceReferenceDate.rounded(.down) + 1)
}
