import Foundation

public enum TimetableRepositoryError: Error, Equatable, LocalizedError {
    case unreadableFile(String)

    public var errorDescription: String? {
        switch self {
        case .unreadableFile(let name):
            "\(name) を読み込めません"
        }
    }
}

/// 保存済みの時刻表を読み込んだ結果
public struct StoredTimetables: Sendable {
    public let timetables: [Timetable]
    /// 読み込めなかったファイル名と理由
    public let failures: [(fileName: String, message: String)]

    /// 駅・路線・方面ごとの時刻表（キーは `Timetable.routeKey`）
    public var byRoute: [String: [Timetable]] {
        Dictionary(grouping: timetables, by: \.routeKey)
    }
}

/// 時刻表 JSON の保存と読み込み。保存先は `~/Library/Application Support/<bundle id>/timetables/`
public struct TimetableRepository: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// アプリの既定の保存先
    public static func defaultDirectory(bundleIdentifier: String) -> URL {
        URL.applicationSupportDirectory
            .appending(path: bundleIdentifier, directoryHint: .isDirectory)
            .appending(path: "timetables", directoryHint: .isDirectory)
    }

    /// 保存済みの時刻表をすべて読み込む。保存先がなければ空。壊れたファイルは `failures` に入れて読み飛ばす
    public func loadAll() -> StoredTimetables {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []

        var timetables: [Timetable] = []
        var failures: [(String, String)] = []
        for file in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                timetables.append(try Timetable.decode(from: Data(contentsOf: file)))
            } catch {
                failures.append((file.lastPathComponent, error.localizedDescription))
            }
        }
        return StoredTimetables(timetables: timetables, failures: failures)
    }

    /// 保存する。同じ駅・路線・方面と改正日の時刻表は上書きする
    @discardableResult
    public func save(_ timetable: Timetable) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(for: timetable)
        try timetable.encoded().write(to: url, options: .atomic)
        return url
    }

    /// `provider` から取得して保存する。取得や検証に失敗した場合は何も保存しない
    @discardableResult
    public func importTimetable(from provider: some TimetableProvider) async throws -> Timetable {
        let timetable = try await provider.fetchTimetable()
        try save(timetable)
        return timetable
    }

    /// 保存済みの時刻表を削除する
    public func delete(_ timetable: Timetable) throws {
        let url = fileURL(for: timetable)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    func fileURL(for timetable: Timetable) -> URL {
        let name = "\(timetable.routeKey)@\(timetable.validFrom)"
            .map { "/:\\".contains($0) ? "_" : String($0) }
            .joined()
        return directory.appending(path: "\(name).json", directoryHint: .notDirectory)
    }
}
