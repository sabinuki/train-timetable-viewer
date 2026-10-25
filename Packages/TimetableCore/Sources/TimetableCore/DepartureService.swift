import Foundation

/// 表示する発車の絞り込み条件。種別や行き先による除外は #16 で追加する
public struct DepartureFilter: Sendable {
    private let predicate: @Sendable (Departure) -> Bool

    public init(_ predicate: @escaping @Sendable (Departure) -> Bool) {
        self.predicate = predicate
    }

    /// すべての発車を表示する
    public static let all = DepartureFilter { _ in true }

    public func includes(_ departure: Departure) -> Bool {
        predicate(departure)
    }
}

/// 現在時刻以降の 1 本の発車
public struct UpcomingDeparture: Hashable, Sendable, Identifiable {
    public let departure: Departure
    /// この発車が属する運行日とダイヤ区分
    public let serviceDay: CalendarDate
    public let calendarKind: CalendarKind
    /// 発車する日時
    public let departureDate: Date
    /// 乗るために出発すべき日時（発車 − 駅までの所要時間）
    public let leaveByDate: Date
    /// 今から出発して間に合うか
    public let isCatchable: Bool

    public var id: String {
        "\(serviceDay)/\(departure.time)/\(departure.type ?? "")/\(departure.destination ?? "")"
    }

    /// 発車までの残り時間（秒）
    public func secondsUntilDeparture(from now: Date) -> TimeInterval {
        departureDate.timeIntervalSince(now)
    }

    /// 出発すべき時刻までの残り時間（秒）
    public func secondsUntilLeave(from now: Date) -> TimeInterval {
        leaveByDate.timeIntervalSince(now)
    }
}

/// ある時点の発車一覧
public struct DepartureBoard: Hashable, Sendable {
    public let now: Date
    /// 現在の運行日とダイヤ区分
    public let serviceDay: CalendarDate
    public let calendarKind: CalendarKind
    /// 現在時刻以降の発車（運行日が終わった後は翌運行日以降の発車）
    public let departures: [UpcomingDeparture]
    /// 現在の運行日に、これ以上発車がないか
    public let isServiceEnded: Bool

    /// 今から出発して乗れる最初の発車
    public var nextCatchable: UpcomingDeparture? {
        departures.first(where: \.isCatchable)
    }
}

/// 現在時刻以降の発車と、出発すべき時刻の算出（設計書 §9.2）
public struct DepartureService: Sendable {
    public var resolver: ServiceDayResolver

    /// 不足分を補うために先読みする運行日の上限
    private static let lookaheadDays = 7

    public init(resolver: ServiceDayResolver) {
        self.resolver = resolver
    }

    /// `now` 以降の発車を最大 `count` 本求める
    /// - Parameters:
    ///   - timetables: 同じ駅・路線・方面の時刻表（ダイヤ改正の前後を含めてよい）
    ///   - minutesToStation: 駅までの所要時間（分）
    /// - Returns: 現在の運行日に有効な時刻表がなければ `nil`
    public func board(
        at now: Date,
        timetables: [Timetable],
        minutesToStation: Int,
        count: Int,
        filter: DepartureFilter = .all
    ) -> DepartureBoard? {
        let moment = resolver.moment(at: now)
        guard let today = Timetable.effective(among: timetables, on: moment.serviceDay) else {
            return nil
        }
        let todayKind = resolver.calendarKind(for: moment.serviceDay, hasSaturdayCalendar: today.hasSaturdayCalendar)

        let todayDepartures = today.departures(for: todayKind).filter(filter.includes)
        let start = todayDepartures.partitioningIndex { $0.time >= moment.time }
        let remainingToday = todayDepartures[start...]

        var upcoming = remainingToday.prefix(count).map {
            makeUpcoming($0, serviceDay: moment.serviceDay, kind: todayKind, now: now, minutesToStation: minutesToStation)
        }

        var serviceDay = moment.serviceDay
        for _ in 0..<Self.lookaheadDays where upcoming.count < count {
            serviceDay = serviceDay.adding(days: 1)
            guard let timetable = Timetable.effective(among: timetables, on: serviceDay) else { continue }
            let kind = resolver.calendarKind(for: serviceDay, hasSaturdayCalendar: timetable.hasSaturdayCalendar)
            let departures = timetable.departures(for: kind).filter(filter.includes)
            upcoming += departures.prefix(count - upcoming.count).map {
                makeUpcoming($0, serviceDay: serviceDay, kind: kind, now: now, minutesToStation: minutesToStation)
            }
        }

        return DepartureBoard(
            now: now,
            serviceDay: moment.serviceDay,
            calendarKind: todayKind,
            departures: upcoming,
            isServiceEnded: remainingToday.isEmpty)
    }

    private func makeUpcoming(
        _ departure: Departure,
        serviceDay: CalendarDate,
        kind: CalendarKind,
        now: Date,
        minutesToStation: Int
    ) -> UpcomingDeparture {
        let departureDate = resolver.date(serviceDay: serviceDay, time: departure.time)
        let leaveByDate = departureDate.addingTimeInterval(TimeInterval(-max(0, minutesToStation) * 60))
        return UpcomingDeparture(
            departure: departure,
            serviceDay: serviceDay,
            calendarKind: kind,
            departureDate: departureDate,
            leaveByDate: leaveByDate,
            isCatchable: now <= leaveByDate)
    }
}

extension Array {
    /// `belongsToSecondPartition` が true になる最初の位置（配列はその条件で分割済みであること）
    func partitioningIndex(where belongsToSecondPartition: (Element) -> Bool) -> Int {
        var low = 0
        var high = count
        while low < high {
            let mid = (low + high) / 2
            if belongsToSecondPartition(self[mid]) {
                high = mid
            } else {
                low = mid + 1
            }
        }
        return low
    }
}
