import Foundation

/// 祝日データの自動更新（設計書 §4.1）。
/// 内閣府の CSV を定期的に取得して保存し、同梱版より新しければそちらを使う
public struct HolidayUpdater: Sendable {
    /// 取得した CSV の保存先
    public let storageURL: URL
    /// 前回の取得からこの期間が過ぎていれば取得し直す
    public let interval: TimeInterval

    public static let sourceURL = URL(string: "https://www8.cao.go.jp/chosei/shukujitsu/syukujitsu.csv")!
    public static let defaultInterval: TimeInterval = 30 * 24 * 60 * 60

    public typealias Fetch = @Sendable (URL) async throws -> Data

    public init(storageURL: URL, interval: TimeInterval = Self.defaultInterval) {
        self.storageURL = storageURL
        self.interval = interval
    }

    /// アプリの既定の保存先
    public static func defaultStorageURL(bundleIdentifier: String) -> URL {
        URL.applicationSupportDirectory
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "holidays", directoryHint: .isDirectory)
            .appending(path: "syukujitsu.csv", directoryHint: .notDirectory)
    }

    /// 保存済みと同梱の CSV のうち、より先の祝日まで収録しているほう。どちらも読めなければ空
    public func loadCurrent(bundled: HolidayCalendar?) -> HolidayCalendar {
        let saved = (try? Data(contentsOf: storageURL)).flatMap { try? HolidayRepository.parse(csv: $0) }
        return Self.newer(saved, bundled) ?? HolidayCalendar(names: [:])
    }

    /// 前回の取得から `interval` が過ぎていれば取得する。
    /// 取得・検証・保存に成功したら新しい祝日データを返す。不要な場合や失敗した場合は `nil`（今のデータを使い続ける）
    public func updateIfNeeded(
        now: Date,
        lastFetched: Date?,
        current: HolidayCalendar,
        fetch: Fetch
    ) async -> HolidayCalendar? {
        if let lastFetched, now.timeIntervalSince(lastFetched) < interval {
            return nil
        }
        guard let data = try? await fetch(Self.sourceURL),
              let fetched = try? HolidayRepository.parse(csv: data),
              Self.isPlausible(fetched, comparedTo: current)
        else { return nil }

        do {
            try FileManager.default.createDirectory(
                at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            return nil
        }
        return fetched
    }

    /// 取得したデータが今のデータより古くなく、件数が極端に少なくないか（壊れたデータや別のファイルを弾く）
    static func isPlausible(_ fetched: HolidayCalendar, comparedTo current: HolidayCalendar) -> Bool {
        guard let fetchedLast = fetched.lastDate else { return false }
        if let currentLast = current.lastDate, fetchedLast < currentLast { return false }
        return fetched.names.count * 2 >= current.names.count
    }

    static func newer(_ lhs: HolidayCalendar?, _ rhs: HolidayCalendar?) -> HolidayCalendar? {
        guard let lhs, let lhsLast = lhs.lastDate else { return rhs }
        guard let rhs, let rhsLast = rhs.lastDate else { return lhs }
        return lhsLast >= rhsLast ? lhs : rhs
    }
}

/// URLSession で取得する（タイムアウト 15 秒、システムのプロキシ設定に従う）
public let urlSessionHolidayFetch: HolidayUpdater.Fetch = { url in
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.cachePolicy = .reloadIgnoringLocalCacheData
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        throw URLError(.badServerResponse)
    }
    return data
}
