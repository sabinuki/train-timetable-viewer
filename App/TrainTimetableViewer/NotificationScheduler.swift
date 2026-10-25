import AppKit
import Observation
import TimetableCore
import UserNotifications

/// 出発すべき時刻の前の通知を登録する（設計書 §9.4）。
/// 通知は同じ識別子で常に 1 件だけ登録し、対象が変わったときだけ差し替える
@MainActor
@Observable
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    @ObservationIgnored private var scheduled: PlannedNotification?
    @ObservationIgnored private let center = UNUserNotificationCenter.current()

    private static let identifier = "next-departure"

    override init() {
        super.init()
        center.delegate = self
        Task { await refreshAuthorizationStatus() }
    }

    var isDenied: Bool {
        authorizationStatus == .denied
    }

    /// 通知の許可を求める（通知をオンにしたとき）
    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
        await refreshAuthorizationStatus()
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await Self.currentAuthorizationStatus()
    }

    /// `UNNotificationSettings` は SDK によって Sendable でないため、メインアクターの外で状態だけを取り出す
    private nonisolated static func currentAuthorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// 次に出す通知を登録し直す。対象が前回と同じなら何もしない
    func update(_ planned: PlannedNotification?) {
        guard planned != scheduled else { return }
        scheduled = planned
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier])
        guard let planned, planned.fireDate > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = .default
        // スリープをまたいでも時刻どおりに出るよう、経過時間ではなく日時で指定する
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: planned.fireDate)
        let request = UNNotificationRequest(
            identifier: Self.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        center.add(request)
    }

    /// メニューバー常駐アプリは常に前面扱いになるため、前面でもバナーを出す
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
