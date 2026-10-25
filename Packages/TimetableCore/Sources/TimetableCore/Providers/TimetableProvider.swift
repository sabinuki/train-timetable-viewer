import Foundation

/// 時刻表の取得元（設計書 §4 の方針）。ODPT からの取得は #22 で追加する
public protocol TimetableProvider: Sendable {
    func fetchTimetable() async throws -> Timetable
}

/// 時刻表 JSON ファイルからの取り込み
public struct LocalFileProvider: TimetableProvider {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func fetchTimetable() async throws -> Timetable {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw TimetableRepositoryError.unreadableFile(url.lastPathComponent)
        }
        return try Timetable.decode(from: data)
    }
}
