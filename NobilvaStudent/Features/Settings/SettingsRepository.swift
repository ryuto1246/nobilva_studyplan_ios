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

    /// `/profile/user-info` には student が含まれないため、学習設定・ポモドーロ・
    /// 招待コードはこちらから取る。
    func studentProfile() async throws -> StudentProfile {
        try await api.get("/api/v1/student/profile/student")
    }

    /// 行がまだ無いユーザーは null が返るので optional。
    func notifications() async throws -> NotificationPreferences? {
        try await api.get("/api/v1/student/settings/notifications")
    }

    /// サーバ (lib/domain/line.ts) は camelCase で読み、未指定のキーは既定値で上書きする。
    /// そのため 3 項目すべてを毎回送る。
    struct NotificationPatchBody: Encodable {
        let chatNotifications: Bool
        let meetingReminders: Bool
        let meetingReminderMinutes: Int
    }

    func patchNotifications(_ body: NotificationPatchBody) async throws {
        let _: EmptyResponse = try await api.patch("/api/v1/student/settings/notifications", body: body)
    }
}
