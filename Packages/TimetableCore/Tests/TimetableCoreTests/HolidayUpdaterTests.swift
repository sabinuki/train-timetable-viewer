import Foundation
import Testing
@testable import TimetableCore

private final class TemporaryDirectory {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "HolidayUpdaterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    deinit { try? FileManager.default.removeItem(at: url) }
}

private func csv(_ rows: [String]) -> Data {
    ("国民の祝日・休日月日,国民の祝日・休日名称\r\n" + rows.joined(separator: "\r\n") + "\r\n").data(using: .shiftJIS)!
}

/// 呼ばれた回数を数える取得処理
private final class FetchSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var _count = 0
    var count: Int { lock.withLock { _count } }
    func record() { lock.withLock { _count += 1 } }
}

@Suite struct HolidayUpdaterTests {
    private let temporary = TemporaryDirectory()
    private var updater: HolidayUpdater {
        HolidayUpdater(storageURL: temporary.url.appending(path: "holidays/syukujitsu.csv"))
    }
    private let bundled = HolidayCalendar(names: [
        CalendarDate(year: 2027, month: 1, day: 1): "元日",
        CalendarDate(year: 2027, month: 11, day: 23): "勤労感謝の日",
    ])
    private let now = tokyoDate(2026, 10, 25, 12, 0)
    private let newer = csv(["2027/1/1,元日", "2027/11/23,勤労感謝の日", "2028/1/1,元日"])

    @Test func usesBundledWhenNothingSaved() {
        #expect(updater.loadCurrent(bundled: bundled) == bundled)
    }

    @Test func skipsFetchWithinInterval() async {
        let spy = FetchSpy()
        let result = await updater.updateIfNeeded(
            now: now, lastFetched: now.addingTimeInterval(-29 * 24 * 3600), current: bundled
        ) { _ in spy.record(); return Data() }
        #expect(result == nil)
        #expect(spy.count == 0)
    }

    @Test func fetchesSavesAndPrefersNewerData() async throws {
        let newer = newer
        let result = await updater.updateIfNeeded(
            now: now, lastFetched: now.addingTimeInterval(-31 * 24 * 3600), current: bundled
        ) { url in
            #expect(url == HolidayUpdater.sourceURL)
            return newer
        }
        let updated = try #require(result)
        #expect(updated.isHoliday(CalendarDate(year: 2028, month: 1, day: 1)))
        // 保存したデータが次回起動時に同梱版より優先される
        #expect(updater.loadCurrent(bundled: bundled) == updated)
    }

    @Test func fetchesWhenNeverFetched() async {
        let newer = newer
        #expect(await updater.updateIfNeeded(now: now, lastFetched: nil, current: bundled) { _ in newer } != nil)
    }

    @Test func offlineKeepsCurrentData() async {
        let result = await updater.updateIfNeeded(now: now, lastFetched: nil, current: bundled) { _ in
            throw URLError(.notConnectedToInternet)
        }
        #expect(result == nil)
        #expect(updater.loadCurrent(bundled: bundled) == bundled)
    }

    @Test func rejectsInvalidOrOlderData() async {
        let broken = Data("<html>メンテナンス中</html>".utf8)
        #expect(await updater.updateIfNeeded(now: now, lastFetched: nil, current: bundled) { _ in broken } == nil)

        let older = csv(["2026/1/1,元日"])
        #expect(await updater.updateIfNeeded(now: now, lastFetched: nil, current: bundled) { _ in older } == nil)
        #expect(!FileManager.default.fileExists(atPath: updater.storageURL.path))
    }

    @Test func bundledWinsWhenSavedIsOlder() throws {
        // アプリの更新で同梱版のほうが新しくなった場合
        try FileManager.default.createDirectory(at: updater.storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try csv(["2026/1/1,元日"]).write(to: updater.storageURL)
        #expect(updater.loadCurrent(bundled: bundled) == bundled)
    }

    @Test func brokenSavedFileFallsBackToBundled() throws {
        try FileManager.default.createDirectory(at: updater.storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("broken".utf8).write(to: updater.storageURL)
        #expect(updater.loadCurrent(bundled: bundled) == bundled)
    }

    @Test func holidaysLastFetchedPersists() {
        let suite = "HolidayUpdaterTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AppSettings(defaults: defaults)
        #expect(settings.holidaysLastFetched == nil)
        settings.holidaysLastFetched = now
        #expect(AppSettings(defaults: defaults).holidaysLastFetched == now)
    }
}
