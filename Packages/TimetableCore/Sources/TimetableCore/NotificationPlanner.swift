import Foundation

/// 登録する通知 1 件
public struct PlannedNotification: Hashable, Sendable {
    /// 通知する日時
    public let fireDate: Date
    public let title: String
    public let body: String
    /// 対象の発車（同じ通知を登録し直さないための比較用）
    public let departureID: String
}

/// 次に出す通知を決める（設計書 §9.4）
public enum NotificationPlanner {
    /// 乗れる発車のうち、通知する日時（出発すべき時刻 − X 分）がまだ来ておらず、時間帯に入る最初の 1 本の通知
    public static func plan(
        board: DepartureBoard?,
        profile: RouteProfile?,
        now: Date,
        calendar: Calendar
    ) -> PlannedNotification? {
        guard let board, let profile, profile.notification.isEnabled else { return nil }
        let settings = profile.notification

        for upcoming in board.departures where upcoming.isCatchable {
            let fireDate = upcoming.leaveByDate.addingTimeInterval(TimeInterval(-settings.minutesBefore * 60))
            guard fireDate > now else { continue }
            let components = calendar.dateComponents([.hour, .minute], from: fireDate)
            guard settings.isInWindow(minuteOfDay: components.hour! * 60 + components.minute!) else { continue }

            let departure = upcoming.departure
            let time = departure.time.clockDescription
            let leaveBy = clockText(upcoming.leaveByDate, calendar: calendar)
            let label = [departure.type, departure.destination.map { "\($0)行" }].compactMap(\.self).joined(separator: " ")
            let title = settings.minutesBefore == 0
                ? "\(time) 発に乗るなら、今出発しましょう"
                : "\(time) 発に乗るなら、あと \(settings.minutesBefore) 分で出発"
            let body = "\(leaveBy) までに出発（\(profile.name)\(label.isEmpty ? "" : "・\(label)")）"
            return PlannedNotification(fireDate: fireDate, title: title, body: body, departureID: upcoming.id)
        }
        return nil
    }

    private static func clockText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return ServiceTime(hour: components.hour!, minute: components.minute!).description
    }
}
