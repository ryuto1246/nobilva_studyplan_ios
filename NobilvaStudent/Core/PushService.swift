import Foundation
import UserNotifications
import UIKit

/// Push Notification / ローカル通知の基盤。
/// - ユーザーに通知許可を要求
/// - APNs Device Token を取得してログに残す (サーバ側の受け皿 endpoint 未実装のため送信はしない)
/// - ローカル通知 (ポモドーロ完了通知など) のスケジューラ
///
/// 将来サーバ側に `/api/v1/student/settings/notifications/apns` などが用意された時点で
/// `registerTokenWithServer(_:)` の TODO を埋める。
@MainActor
final class PushService: NSObject {
    static let shared = PushService()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// アプリ起動直後 (ログイン後推奨) に呼ぶ。許可要求 → APNs 登録。
    func requestAuthorizationAndRegister() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            Log.ui.info("notification permission granted: \(granted)")
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            }
        } catch {
            Log.ui.error("requestAuthorization failed: \(String(describing: error))")
        }
    }

    /// AppDelegate の `didRegisterForRemoteNotificationsWithDeviceToken` で呼ぶ想定。
    /// 現状はサーバへの登録 endpoint が無いのでログのみ。
    func registerDeviceToken(_ tokenData: Data) {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        Log.ui.info("APNs device token: \(hex)")
        // TODO: サーバ側 endpoint 実装後、Bearer 認証で送信する
    }

    // MARK: - Local scheduling helpers

    /// ポモドーロ 1 セット完了時などにアプリがフォアグラウンドでない状況を想定した
    /// ローカル通知のスケジューリング。既存の同 identifier は上書き。
    func scheduleLocal(after seconds: TimeInterval, title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, seconds), repeats: false)
        let req = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }

    func cancelLocal(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}

extension PushService: UNUserNotificationCenterDelegate {
    /// フォアグラウンドでも通知を出す。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }
}
