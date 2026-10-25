import Foundation
import Observation
import TimetableCore

/// アプリ全体の状態。時刻表の保存先と、表示状態、再計算のタイミングをまとめる
@MainActor
@Observable
final class AppModel {
    let viewModel: DepartureBoardViewModel
    /// 保存済みの時刻表のうち、読み込めなかったもの
    private(set) var loadFailures: [String] = []

    @ObservationIgnored let repository: TimetableRepository
    @ObservationIgnored private var clock: RefreshClock?

    init(defaults: UserDefaults = .standard) {
        let holidays = (try? HolidayRepository.loadBundled()) ?? HolidayCalendar(names: [:])
        viewModel = DepartureBoardViewModel(
            service: DepartureService(resolver: ServiceDayResolver(holidays: holidays)),
            settings: AppSettings(defaults: defaults))
        repository = TimetableRepository(
            directory: TimetableRepository.defaultDirectory(
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.sabinuki.TrainTimetableViewer"))

        reloadTimetables()
        let clock = RefreshClock { [weak self] in self?.viewModel.refresh() }
        clock.start()
        self.clock = clock
    }

    /// 保存済みの時刻表を読み込み直す
    func reloadTimetables() {
        let stored = repository.loadAll()
        loadFailures = stored.failures.map { "\($0.fileName): \($0.message)" }
        viewModel.load(stored.timetables)
    }
}
