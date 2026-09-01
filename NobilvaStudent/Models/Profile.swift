import Foundation

struct Profile: Codable, Identifiable, Hashable {
    let id: String
    let role: String
    let displayName: String
    let avatarUrl: String?
    let onboardingCompleted: Bool?
    let mustChangePassword: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, role
        case displayName = "display_name"
        case avatarUrl = "avatar_url"
        case onboardingCompleted = "onboarding_completed"
        case mustChangePassword = "must_change_password"
        case createdAt = "created_at"
    }
}

enum GradeLevel: String, Codable, CaseIterable, Identifiable {
    case elementary, middle, high, ronin
    var id: String { rawValue }
    var label: String {
        switch self {
        case .elementary: return "小学生"
        case .middle: return "中学生"
        case .high: return "高校生"
        case .ronin: return "浪人生"
        }
    }
}

struct StudentProfile: Codable, Identifiable, Hashable {
    let id: String
    let userId: String
    let gradeLevel: GradeLevel?
    let dailyAvailableMinutes: Int
    let pomodoroWorkMinutes: Int
    let pomodoroBreakMinutes: Int
    let pomodoroLongBreakMinutes: Int
    let inviteCode: String?
    let aiPlanEnabled: Bool?
    let tags: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case gradeLevel = "grade_level"
        case dailyAvailableMinutes = "daily_available_minutes"
        case pomodoroWorkMinutes = "pomodoro_work_minutes"
        case pomodoroBreakMinutes = "pomodoro_break_minutes"
        case pomodoroLongBreakMinutes = "pomodoro_long_break_minutes"
        case inviteCode = "invite_code"
        case aiPlanEnabled = "ai_plan_enabled"
        case tags
    }
}

/// `/profile/user-info` の複合レスポンス。
struct StudentUserInfo: Codable {
    let profile: Profile
    let student: StudentProfile?
    let email: String?
}
