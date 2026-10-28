import Foundation
import UserNotifications
import UIKit

/// Push Notification / ローカル通知の基盤。
/// - ユーザーに通知許可を要求
/// - APNs Device Token を取得 → サーバの `/api/v1/student/settings/apns` に POST
/// - ローカル通知 (ポモドーロ完了通知など) のスケジューラ
///
/// device token は非同期で AppDelegate に届くので、届いたときに APIClient
/// (認証済み) がまだ無い可能性がある。その場合はメモリに保持しておき、
/// `attach(api:)` が呼ばれた時点で送信する。
@MainActor
final class PushService: NSObject {
    static let shared = PushService()

    /// APIClient は AuthStore からセッションが確立された時に注入される (weak)。
    /// PushService は認証周りに依存しないので、api が nil のときは送信を保留する。
    private weak var api: APIClient?
    /// 未送信のトークン (hex)。attach 後に flush する。
    private var pendingTokenHex: String?
    /// サーバに登録済みのこの端末のトークン。サインアウト時にこの端末分だけ消すのに使う。
    private var registeredTokenHex: String?

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// AuthStore init 内で呼ぶ。APIClient を渡し、保留トークンがあれば送る。
    func attach(api: APIClient) {
        self.api = api
        if pendingTokenHex != nil { flushPendingToken() }
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

    /// AppDelegate の `didRegisterForRemoteNotificationsWithDeviceToken` で呼ぶ。
    /// api が既に attach されていれば即送信、そうでなければ保留して attach 時に送る。
    func registerDeviceToken(_ tokenData: Data) {
        let hex = tokenData.map { String(format: "%02x", $0) }.joined()
        pendingTokenHex = hex
        Log.ui.info("APNs device token received (len=\(hex.count))")
        if api != nil { flushPendingToken() }
    }

    /// サインアウト時に呼ぶ。サーバ側のデバイストークン行を消しつつローカルもクリア。
    func unregisterOnSignOut() async {
        let token = registeredTokenHex ?? pendingTokenHex
        pendingTokenHex = nil
        registeredTokenHex = nil
        guard let api else { return }
        do {
            // device_token を付けると、他の端末の通知は止めずにこの端末の分だけ消える。
            let _: OKResponse = try await api.delete(
                "/api/v1/student/settings/apns",
                query: token.map { ["device_token": $0] } ?? [:]
            )
        } catch {
            // 落ちても致命ではないので warn だけ。
            Log.ui.error("APNs unregister failed: \(String(describing: error))")
        }
    }

    private func flushPendingToken() {
        guard let hex = pendingTokenHex, let api else { return }
        let device = UIDevice.current
        let body = ApnsRegisterBody(
            device_token: hex,
            device_name: device.name,
            device_id: device.identifierForVendor?.uuidString
        )
        Task { [weak self] in
            do {
                let _: OKResponse = try await api.post(
                    "/api/v1/student/settings/apns",
                    body: body
                )
                await MainActor.run {
                    self?.registeredTokenHex = hex
                    // 送信中に新しいトークンが届いていたら消さずに残す。
                    if self?.pendingTokenHex == hex { self?.pendingTokenHex = nil }
                }
            } catch {
                // 失敗時は pendingTokenHex を残し、次の attach / register で再送される。
                Log.ui.error("APNs token register failed: \(String(describing: error))")
            }
        }
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

// MARK: - Wire types

private struct ApnsRegisterBody: Encodable {
    let device_token: String
    let device_name: String?
    let device_id: String?
}

private struct OKResponse: Decodable {
    let ok: Bool?
}
