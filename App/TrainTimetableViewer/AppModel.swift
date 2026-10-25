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
    /// グローバルショートカットを登録できたか
    private(set) var isHotKeyRegistered = false

    @ObservationIgnored let repository: TimetableRepository
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private var clock: RefreshClock?
    @ObservationIgnored private var hotKey: GlobalHotKey?

    init(defaults: UserDefaults = .standard) {
        settings = AppSettings(defaults: defaults)
        let holidays = (try? HolidayRepository.loadBundled()) ?? HolidayCalendar(names: [:])
        viewModel = DepartureBoardViewModel(
            service: DepartureService(resolver: ServiceDayResolver(holidays: holidays)),
            settings: settings)
        repository = TimetableRepository(
            directory: TimetableRepository.defaultDirectory(
                bundleIdentifier: Bundle.main.bundleIdentifier ?? "com.sabinuki.TrainTimetableViewer"))

        reloadTimetables()
        let clock = RefreshClock { [weak self] in self?.viewModel.refresh() }
        clock.start()
        self.clock = clock
        setUpPanel()

        let hotKey = GlobalHotKey { [weak self] in self?.togglePanel() }
        isHotKeyRegistered = hotKey.register()
        self.hotKey = hotKey
    }

    // MARK: - パネル

    private(set) var isPanelVisible = false
    var canShowPanel: Bool { panel != nil }
    @ObservationIgnored private var panel: FloatingPanelController?

    /// パネルを用意し、前回の表示状態を復元する
    private func setUpPanel() {
        let panel = FloatingPanelController(rootView: DeparturePanelView(viewModel: viewModel))
        panel.onClose = { [weak self] in self?.panelDidHide() }
        self.panel = panel
        if settings.isPanelVisible {
            showPanel()
        }
    }

    func showPanel() {
        guard let panel else { return }
        // 起動直後は orderFront の直後でも isVisible が false のことがあるため、要求どおりに表示中として扱う
        panel.show()
        isPanelVisible = true
        settings.isPanelVisible = true
    }

    func hidePanel() {
        panel?.hide()
        panelDidHide()
    }

    func togglePanel() {
        if isPanelVisible { hidePanel() } else { showPanel() }
    }

    private func panelDidHide() {
        isPanelVisible = false
        settings.isPanelVisible = false
    }

    // MARK: - 時刻表

    /// 保存済みの時刻表を読み込み直す
    func reloadTimetables() {
        let stored = repository.loadAll()
        loadFailures = stored.failures.map { "\($0.fileName): \($0.message)" }
        viewModel.load(stored.timetables)
    }
}
