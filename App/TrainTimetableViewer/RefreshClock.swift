import AppKit
import TimetableCore

/// 再計算のきっかけを作る（設計書 §9.3）
/// - 毎分 0 秒
/// - スリープ復帰、システム時刻の変更、日付の変更
@MainActor
final class RefreshClock {
    private let onTick: @MainActor () -> Void
    private var timer: Timer?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init(onTick: @escaping @MainActor () -> Void) {
        self.onTick = onTick
    }

    func start() {
        guard observers.isEmpty else { return }
        observe(NSWorkspace.didWakeNotification, in: NSWorkspace.shared.notificationCenter)
        observe(.NSSystemClockDidChange, in: .default)
        observe(.NSCalendarDayChanged, in: .default)
        scheduleNextTick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    private func observe(_ name: Notification.Name, in center: NotificationCenter) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        observers.append((center, observer))
    }

    private func tick() {
        onTick()
        scheduleNextTick()
    }

    /// 次の分の 0 秒に 1 回だけ発火するタイマーを置き直す（スリープでずれても次の発火で揃う）
    private func scheduleNextTick() {
        timer?.invalidate()
        let timer = Timer(fire: nextMinuteBoundary(after: Date()), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
