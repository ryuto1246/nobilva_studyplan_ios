import Foundation

struct TimerRepository {
    let api: APIClient

    // MARK: - Sessions
    /// サーバは plan_item_id が「string か null」であることを要求する。
    /// 合成 Encodable は nil のキーを省くため、null を明示的に書き出す。
    struct StartBody: Encodable {
        let plan_item_id: String?
        let mode: String

        enum CodingKeys: String, CodingKey { case plan_item_id, mode }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(plan_item_id, forKey: .plan_item_id)
            try c.encode(mode, forKey: .mode)
        }
    }

    func start(mode: SessionMode, planItemId: String?) async throws -> SessionStartResponse {
        try await api.post("/api/v1/student/sessions/start",
                           body: StartBody(plan_item_id: planItemId, mode: mode.rawValue))
    }

    struct CompleteBody: Encodable {
        let duration_seconds: Int
    }

    func complete(sessionId: String, durationSeconds: Int) async throws -> SessionCompletedResponse {
        try await api.post("/api/v1/student/sessions/\(sessionId)/complete",
                           body: CompleteBody(duration_seconds: durationSeconds))
    }

    /// 未完了のセッションを消す (記録せずに終了したとき)。
    func cancel(sessionId: String) async throws {
        let _: EmptyResponse = try await api.delete("/api/v1/student/sessions/\(sessionId)")
    }

    struct ManualBody: Encodable {
        let plan_item_id: String?
        let duration_minutes: Int

        enum CodingKeys: String, CodingKey { case plan_item_id, duration_minutes }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(plan_item_id, forKey: .plan_item_id)
            try c.encode(duration_minutes, forKey: .duration_minutes)
        }
    }

    func manual(planItemId: String?, durationMinutes: Int) async throws -> SessionCompletedResponse {
        try await api.post("/api/v1/student/sessions/manual",
                           body: ManualBody(plan_item_id: planItemId, duration_minutes: durationMinutes))
    }

    // MARK: - Pomodoro prefs
    func pomodoroPrefs() async throws -> StudentProfile {
        try await api.get("/api/v1/student/profile/student")
    }
}
