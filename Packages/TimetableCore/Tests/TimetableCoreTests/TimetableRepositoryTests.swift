import Foundation
import Testing
@testable import TimetableCore

private func makeTimetable(station: String = "s", validFrom: String = "2026-03-14", time: String = "18:05") -> Timetable {
    Timetable(
        station: Station(id: station, name: "〇〇駅"),
        line: Line(id: "l", name: "△△線"),
        direction: Direction(id: "d", name: "××方面"),
        validFrom: CalendarDate(string: validFrom)!,
        calendars: [.weekday: [Departure(time: ServiceTime(string: time)!)], .holiday: []])
}

/// テストごとに作って消す一時ディレクトリ
private final class TemporaryDirectory {
    let url = FileManager.default.temporaryDirectory
        .appending(path: "TimetableRepositoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

@Suite struct TimetableRepositoryTests {
    private let temporary = TemporaryDirectory()
    private var repository: TimetableRepository {
        TimetableRepository(directory: temporary.url.appending(path: "timetables"))
    }

    @Test func emptyBeforeFirstSave() {
        let stored = repository.loadAll()
        #expect(stored.timetables.isEmpty)
        #expect(stored.failures.isEmpty)
    }

    @Test func savesAndLoads() throws {
        let timetable = makeTimetable()
        try repository.save(timetable)

        // 別のインスタンス（再起動後に相当）から読み込める
        let reloaded = TimetableRepository(directory: repository.directory).loadAll()
        #expect(reloaded.timetables == [timetable])
    }

    @Test func overwritesSameRouteAndRevision() throws {
        try repository.save(makeTimetable(time: "18:05"))
        try repository.save(makeTimetable(time: "18:10"))
        try repository.save(makeTimetable(validFrom: "2027-03-13"))
        try repository.save(makeTimetable(station: "other"))

        let stored = repository.loadAll()
        #expect(stored.timetables.count == 3)
        #expect(stored.byRoute["s/l/d"]?.count == 2)
        let overwritten = try #require(stored.byRoute["s/l/d"]?.first { $0.validFrom.year == 2026 })
        #expect(overwritten.departures(for: .weekday).first?.time.description == "18:10")
    }

    @Test func fileNameIsSafeForIdsWithSlash() throws {
        let url = try repository.save(makeTimetable(station: "odpt.Station:TokyoMetro/Ginza"))
        #expect(url.deletingLastPathComponent().standardizedFileURL == repository.directory.standardizedFileURL)
        #expect(repository.loadAll().timetables.first?.station.id == "odpt.Station:TokyoMetro/Ginza")
    }

    @Test func skipsBrokenFiles() throws {
        try repository.save(makeTimetable())
        try Data("{".utf8).write(to: repository.directory.appending(path: "broken.json"))
        try Data("not json".utf8).write(to: repository.directory.appending(path: "memo.txt"))

        let stored = repository.loadAll()
        #expect(stored.timetables.count == 1)
        #expect(stored.failures.map(\.fileName) == ["broken.json"])
    }

    @Test func deletes() throws {
        let timetable = makeTimetable()
        try repository.save(timetable)
        try repository.delete(timetable)
        #expect(repository.loadAll().timetables.isEmpty)
        try repository.delete(timetable)  // 存在しなくてもエラーにしない
    }

    @Test func importsValidFile() async throws {
        let source = temporary.url.appending(path: "input.json")
        try FileManager.default.createDirectory(at: temporary.url, withIntermediateDirectories: true)
        try makeTimetable().encoded().write(to: source)

        let imported = try await repository.importTimetable(from: LocalFileProvider(url: source))
        #expect(imported == makeTimetable())
        #expect(repository.loadAll().timetables == [imported])
    }

    @Test func rejectsInvalidFileWithoutSaving() async throws {
        try FileManager.default.createDirectory(at: temporary.url, withIntermediateDirectories: true)
        let invalid = temporary.url.appending(path: "invalid.json")
        try Data(#"{"version": 2}"#.utf8).write(to: invalid)

        await #expect(throws: TimetableError.unsupportedVersion(2)) {
            try await repository.importTimetable(from: LocalFileProvider(url: invalid))
        }
        await #expect(throws: TimetableRepositoryError.unreadableFile("missing.json")) {
            try await repository.importTimetable(from: LocalFileProvider(url: temporary.url.appending(path: "missing.json")))
        }
        #expect(repository.loadAll().timetables.isEmpty)
    }

    @Test func defaultDirectoryIsInApplicationSupport() {
        let url = TimetableRepository.defaultDirectory(bundleIdentifier: "com.example.app")
        #expect(url.path.hasSuffix("Library/Application Support/com.example.app/timetables"))
    }
}
