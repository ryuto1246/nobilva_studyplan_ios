import Foundation

struct SettingsRepository {
    let api: APIClient

    func userInfo() async throws -> StudentUserInfo {
        try await api.get("/api/v1/student/profile/user-info")
    }

    struct ProfilePatchBody: Encodable {
        var display_name: String?
        var grade_level: String?
        var daily_minutes: Int?
    }

    func patchProfile(_ body: ProfilePatchBody) async throws {
        let _: EmptyResponse = try await api.patch("/api/v1/student/profile", body: body)
    }

    struct PomodoroBody: Encodable {
        let work_minutes: Int
        let break_minutes: Int
        let long_break_minutes: Int
    }

    func patchPomodoro(_ body: PomodoroBody) async throws {
        let _: EmptyResponse = try await api.patch("/api/v1/student/settings/pomodoro", body: body)
    }

    func notifications() async throws -> NotificationPreferences {
        try await api.get("/api/v1/student/settings/notifications")
    }

    struct NotificationPatchBody: Encodable {
        var morning_reminder: Bool?
        var morning_reminder_time: String?
        var plan_reminders: Bool?
        var plan_reminder_minutes: Int?
        var evening_summary: Bool?
        var evening_summary_time: String?
        var streak_alerts: Bool?
        var quiet_hours_start: String?
        var quiet_hours_end: String?
        var meeting_reminders: Bool?
        var meeting_reminder_minutes: Int?
    }

    func patchNotifications(_ body: NotificationPatchBody) async throws {
        let _: EmptyResponse = try await api.patch("/api/v1/student/settings/notifications", body: body)
    }
}
