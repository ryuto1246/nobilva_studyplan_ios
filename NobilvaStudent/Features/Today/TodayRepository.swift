import Foundation

/// 今日画面 (dashboard/summary) の取得とステータス更新を担うリポジトリ。
struct TodayRepository {
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

    /// 計画アイテム / タスクどちらでも、完了 ⇄ 未完了を切り替える。
    func setDone(_ item: StudyItem, done: Bool) async throws {
        switch item.kind {
        case .planItem: try await setPlanItemStatus(item.id, status: done ? .completed : .pending)
        case .task: try await setTaskStatus(item.id, status: done ? .completed : .pending)
        }
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
