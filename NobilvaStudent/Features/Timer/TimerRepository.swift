import Foundation

struct TimerRepository {
    let api: APIClient

    // MARK: - Sessions
    struct StartBody: Encodable {
        let plan_item_id: String?
        let mode: String
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

    struct ManualBody: Encodable {
        let plan_item_id: String?
        let duration_minutes: Int
    }

    func manual(planItemId: String?, durationMinutes: Int) async throws -> SessionCompletedResponse {
        try await api.post("/api/v1/student/sessions/manual",
                           body: ManualBody(plan_item_id: planItemId, duration_minutes: durationMinutes))
    }

    // MARK: - Today plan items for picker
    func todayPlan() async throws -> PlanForDate {
        try await api.get("/api/v1/student/plan", query: ["date": JSTDate.todayString()])
    }

    // MARK: - Pomodoro prefs
    func pomodoroPrefs() async throws -> StudentProfile {
        try await api.get("/api/v1/student/profile/student")
    }
}
