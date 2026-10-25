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
    let launchAtLogin = LaunchAtLogin()
    let notifications = NotificationScheduler()

    @ObservationIgnored let repository: TimetableRepository
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let holidayUpdater: HolidayUpdater
    @ObservationIgnored private var clock: RefreshClock?
    @ObservationIgnored private var hotKey: GlobalHotKey?

    init(defaults: UserDefaults = .standard) {
        settings = AppSettings(defaults: defaults)
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.sabinuki.TrainTimetableViewer"
        // 取得済みの祝日データが同梱版より新しければそちらを使う
        holidayUpdater = HolidayUpdater(storageURL: HolidayUpdater.defaultStorageURL(bundleIdentifier: bundleIdentifier))
        let holidays = holidayUpdater.loadCurrent(bundled: try? HolidayRepository.loadBundled())
        viewModel = DepartureBoardViewModel(
            service: DepartureService(resolver: ServiceDayResolver(holidays: holidays)),
            settings: settings)
        repository = TimetableRepository(
            directory: TimetableRepository.defaultDirectory(bundleIdentifier: bundleIdentifier))
        holidaysLastFetched = settings.holidaysLastFetched

        viewModel.onRefresh = { [weak self] in
            guard let self else { return }
            notifications.update(viewModel.plannedNotification)
        }
        reloadTimetables()
        let clock = RefreshClock { [weak self] in self?.viewModel.refresh() }
        clock.perSecond = viewModel.showsSeconds
        clock.start()
        self.clock = clock
        setUpPanel()

        hotKeySetting = settings.hotKey
        let hotKey = GlobalHotKey(setting: hotKeySetting) { [weak self] in self?.togglePanel() }
        isHotKeyRegistered = hotKey.register()
        self.hotKey = hotKey

        Task { await updateHolidays() }
    }

    // MARK: - 祝日データ

    /// 祝日データを最後に取得できた日時
    private(set) var holidaysLastFetched: Date?
    private(set) var isUpdatingHolidays = false
    /// 直近の手動更新の結果
    private(set) var holidayUpdateMessage: String?

    /// 前回の取得から 30 日以上たっていれば内閣府の CSV を取得する。`force` なら期間にかかわらず取得する。
    /// オフラインなどで失敗した場合は、今の祝日データ（保存済みまたは同梱）を使い続ける
    func updateHolidays(force: Bool = false) async {
        guard !isUpdatingHolidays else { return }
        isUpdatingHolidays = true
        defer { isUpdatingHolidays = false }

        let updated = await holidayUpdater.updateIfNeeded(
            now: Date(),
            lastFetched: force ? nil : settings.holidaysLastFetched,
            current: viewModel.holidays,
            fetch: urlSessionHolidayFetch)
        if let updated {
            viewModel.setHolidays(updated)
            let now = Date()
            settings.holidaysLastFetched = now
            holidaysLastFetched = now
            holidayUpdateMessage = force ? "更新しました" : nil
        } else if force {
            holidayUpdateMessage = "取得できませんでした。ネットワークを確認してください"
        }
    }

    // MARK: - 表示

    /// 残り時間を秒単位で表示するか。オンのときだけ毎秒再計算する
    var showsSeconds: Bool {
        get { viewModel.showsSeconds }
        set {
            viewModel.showsSeconds = newValue
            clock?.perSecond = newValue
        }
    }

    // MARK: - グローバルショートカット

    private(set) var hotKeySetting: HotKeySetting = .default

    /// ショートカットを変更する。登録できなければ元に戻して false
    @discardableResult
    func setHotKey(_ setting: HotKeySetting) -> Bool {
        guard let hotKey else { return false }
        if hotKey.update(setting) {
            hotKeySetting = setting
            settings.hotKey = setting
            isHotKeyRegistered = true
            return true
        }
        isHotKeyRegistered = hotKey.update(hotKeySetting)
        return false
    }

    /// 設定画面でキーを記録している間は、今のショートカットを外す（押したキーで切り替わらないように）
    func suspendHotKey() {
        hotKey?.unregister()
    }

    func resumeHotKey() {
        isHotKeyRegistered = hotKey?.update(hotKeySetting) ?? false
    }

    // MARK: - パネル

    private(set) var isPanelVisible = false
    var canShowPanel: Bool { panel != nil }
    @ObservationIgnored private var panel: FloatingPanelController?

    /// パネルの不透明度（0.3〜1.0）
    var panelOpacity: Double = 1.0 {
        didSet {
            settings.panelOpacity = panelOpacity
            panel?.setOpacity(settings.panelOpacity)
        }
    }

    /// パネルへのクリックを下のウィンドウに素通しするか（解除はメニューバーから）
    var isClickThrough = false {
        didSet {
            settings.isClickThrough = isClickThrough
            panel?.setClickThrough(isClickThrough)
        }
    }

    /// パネルを用意し、前回の表示状態を復元する
    private func setUpPanel() {
        let panel = FloatingPanelController(rootView: DeparturePanelView(viewModel: viewModel))
        panel.onClose = { [weak self] in self?.panelDidHide() }
        self.panel = panel
        panelOpacity = settings.panelOpacity
        isClickThrough = settings.isClickThrough
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

    /// 保存済みの時刻表（駅・路線・方面、改正日の順）
    private(set) var storedTimetables: [Timetable] = []

    /// 保存済みの時刻表を読み込み直す
    func reloadTimetables() {
        let stored = repository.loadAll()
        loadFailures = stored.failures.map { "\($0.fileName): \($0.message)" }
        storedTimetables = stored.timetables.sorted {
            ($0.routeKey, $0.validFrom) < ($1.routeKey, $1.validFrom)
        }
        viewModel.load(stored.timetables)
    }

    /// 時刻表 JSON を取り込み、その駅・路線・方面を表示する
    @discardableResult
    func importTimetable(from url: URL) async throws -> Timetable {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let timetable = try await repository.importTimetable(from: LocalFileProvider(url: url))
        reloadTimetables()
        viewModel.showRoute(timetable.routeKey)
        return timetable
    }

    /// アプリに同梱したサンプル時刻表
    var sampleTimetableURL: URL? {
        Bundle.main.url(forResource: "SampleTimetable", withExtension: "json")
    }

    func deleteTimetable(_ timetable: Timetable) throws {
        try repository.delete(timetable)
        reloadTimetables()
    }
}
