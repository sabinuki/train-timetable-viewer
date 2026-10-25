/// 運行日の開始（0:00）からの経過分で表した時刻。終電の `24:21` は 1461 になる。
public struct ServiceTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let minutes: Int

    /// 表記できる時の上限（`47:59` まで）
    public static let maxHour = 47

    public init(minutes: Int) {
        self.minutes = minutes
    }

    public init(hour: Int, minute: Int) {
        self.minutes = hour * 60 + minute
    }

    /// `HH:mm` 形式（時は 0〜47）から作る。不正な表記は `nil`
    public init?(string: String) {
        let parts = string.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              (1...2).contains(parts[0].count), parts[1].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) }),
              let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...Self.maxHour).contains(hour), (0...59).contains(minute)
        else { return nil }
        self.init(hour: hour, minute: minute)
    }

    public var hour: Int { minutes / 60 }
    public var minute: Int { minutes % 60 }

    /// 運行日基準の表記（例: `24:21`）
    public var description: String {
        let hourText = hour < 10 ? "0\(hour)" : "\(hour)"
        let minuteText = minute < 10 ? "0\(minute)" : "\(minute)"
        return "\(hourText):\(minuteText)"
    }

    /// 時計の表記（例: `24:21` → `00:21`）
    public var clockDescription: String {
        ServiceTime(minutes: minutes % (24 * 60)).description
    }

    public static func < (lhs: ServiceTime, rhs: ServiceTime) -> Bool {
        lhs.minutes < rhs.minutes
    }
}
