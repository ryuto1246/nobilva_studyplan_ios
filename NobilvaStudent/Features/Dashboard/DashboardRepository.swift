import Foundation

/// Dashboard 集約 API と個別リフレッシュを担うリポジトリ。
struct DashboardRepository {
    let api: APIClient

    /// ホーム画面の 7 種類のデータを 1 リクエストで取得。成功時にディスクキャッシュ更新。
    func fetchSummary() async throws -> DashboardSummary {
        let summary: DashboardSummary = try await api.get("/api/v1/student/dashboard/summary")
        DiskCache.write(summary, key: .dashboardSummary)
        return summary
    }

    /// 起動直後の空白時間を埋めるためのローカル即応。
    static func cachedSummary() -> DashboardSummary? {
        DiskCache.read(DashboardSummary.self, key: .dashboardSummary)
    }

    /// PlanItem のステータス更新 (Todo チェック用)。
    struct StatusBody: Encodable { let status: String }

    func setPlanItemStatus(_ id: String, status: PlanItemStatus) async throws {
        let _: EmptyResponse = try await api.patch(
            "/api/v1/student/plan/items/\(id)/status",
            body: StatusBody(status: status.rawValue)
        )
    }

    /// StudentTask のステータス更新 (期限切れタスクの完了トグル用)。
    /// plan_items ではなく tasks テーブル側の status を直接更新する。
    func setTaskStatus(_ id: String, status: TaskStatus) async throws {
        let _: EmptyResponse = try await api.patch(
            "/api/v1/student/tasks/\(id)/status",
            body: StatusBody(status: status.rawValue)
        )
    }
}
