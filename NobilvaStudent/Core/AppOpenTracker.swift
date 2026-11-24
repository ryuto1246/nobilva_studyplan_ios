import UIKit

/// アプリを開いたこと自体をサーバに記録する (`POST /api/v1/student/app-opens`)。
///
/// 学習記録が無い日でも「アプリは開いているか」を講師・管理者が生徒詳細で
/// 確認できるようにするためのもの。生徒側の画面には何も出さない。
///
/// 呼ぶタイミングは MainTabView から:
/// - ログイン済みでメイン画面が出たとき (コールドスタート / ログイン直後)
/// - バックグラウンドからフォアグラウンドに戻ったとき
/// 失敗しても生徒の操作には関係ないので、ログだけ残して握りつぶす。
@MainActor
final class AppOpenTracker {
    static let shared = AppOpenTracker()
    private init() {}

    /// 同じ起動を二重に送らないための端末側の間引き。サーバ側でも 1 分以内の
    /// 同一端末からの記録は捨てているが、往復自体を減らしておく。
    private let minInterval: TimeInterval = 60
    private var lastSentAt: Date?
    private var inFlight = false

    func record(api: APIClient) async {
        if inFlight { return }
        if let lastSentAt, Date().timeIntervalSince(lastSentAt) < minInterval { return }
        inFlight = true
        defer { inFlight = false }

        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        let body = AppOpenBody(
            platform: "ios",
            app_version: [version, build].compactMap { $0 }.joined(separator: "+"),
            device_id: UIDevice.current.identifierForVendor?.uuidString
        )
        do {
            let _: AppOpenResponse = try await api.post("/api/v1/student/app-opens", body: body)
            lastSentAt = Date()
        } catch {
            Log.ui.error("app open record failed: \(String(describing: error))")
        }
    }
}

private struct AppOpenBody: Encodable {
    let platform: String
    let app_version: String
    let device_id: String?
}

private struct AppOpenResponse: Decodable {
    let ok: Bool?
}
