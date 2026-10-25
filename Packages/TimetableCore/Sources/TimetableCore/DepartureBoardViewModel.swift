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
    public private(set) var selectedRouteKey: String?

    /// 駅までの所要時間（分）。変更すると保存して再計算する
    public var minutesToStation: Int {
        didSet {
            settings.minutesToStation = minutesToStation
            if minutesToStation != settings.minutesToStation {
                minutesToStation = settings.minutesToStation
            }
            refresh()
        }
    }

    public let displayCount: Int

    @ObservationIgnored private let service: DepartureService
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let now: () -> Date

    public init(service: DepartureService, settings: AppSettings, now: @escaping () -> Date = Date.init) {
        self.service = service
        self.settings = settings
        self.now = now
        self.minutesToStation = settings.minutesToStation
        self.displayCount = settings.displayCount
        self.selectedRouteKey = settings.selectedRouteKey
    }

    /// 保存済みの時刻表を読み込み直す。選択中の路線がなければ最初の路線を選ぶ
    public func load(_ timetables: [Timetable]) {
        routes = Dictionary(grouping: timetables, by: \.routeKey)
        if selectedRouteKey.map({ routes[$0] == nil }) ?? true {
            selectedRouteKey = routes.keys.sorted().first
            settings.selectedRouteKey = selectedRouteKey
        }
        refresh()
    }

    /// 表示する駅・路線・方面を選ぶ（取り込んだ直後など）
    public func selectRoute(_ routeKey: String) {
        guard routes[routeKey] != nil else { return }
        selectedRouteKey = routeKey
        settings.selectedRouteKey = routeKey
        refresh()
    }

    /// 現在時刻で再計算する
    public func refresh() {
        let date = now()
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
                at: date, timetables: timetables, minutesToStation: minutesToStation, count: displayCount)
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

    // MARK: - 表示用の文字列

    /// メニューバーに出す次発（乗れる次発。なければ最初の発車）
    public var headlineDeparture: UpcomingDeparture? {
        board?.nextCatchable ?? board?.departures.first
    }

    /// メニューバーの表示（例: `18:05 あと12分`）
    public var menuBarTitle: String {
        switch status {
        case .noTimetable:
            return "時刻表なし"
        case .notYetEffective(let date):
            return "\(date.month)/\(date.day) から"
        case .ready:
            guard let board, let departure = headlineDeparture else { return "本日終了" }
            let time = departure.departure.time.clockDescription
            if board.isServiceEnded {
                return "始発 \(time)"
            }
            return "\(time) \(remainingText(until: departure.departureDate))"
        }
    }

    /// 発車や出発すべき時刻までの残り時間（例: `あと12分`）
    public func remainingText(until date: Date) -> String {
        let minutes = Int((date.timeIntervalSince(board?.now ?? now()) / 60).rounded(.down))
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
