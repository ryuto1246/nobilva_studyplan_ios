import Foundation

enum PlanItemStatus: String, Codable, CaseIterable, Identifiable {
    case pending, inProgress = "in_progress", completed, skipped
    var id: String { rawValue }
    var isDone: Bool { self == .completed || self == .skipped }
    var label: String {
        switch self {
        case .pending: return "未着手"
        case .inProgress: return "取り組み中"
        case .completed: return "完了"
        case .skipped: return "スキップ"
        }
    }
}

struct StudyPlanPeriod: Codable, Identifiable, Hashable {
    let id: String
    let studentId: String
    let startDate: String
    let endDate: String
    let title: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case studentId = "student_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case title
        case createdAt = "created_at"
    }
}

struct StudyPlan: Codable, Identifiable, Hashable {
    let id: String
    let studentId: String
    let planDate: String
    let planType: String?
    let periodId: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case studentId = "student_id"
        case planDate = "plan_date"
        case planType = "plan_type"
        case periodId = "period_id"
        case createdAt = "created_at"
    }
}

struct PlanItem: Codable, Identifiable, Hashable {
    let id: String
    let planId: String
    let taskId: String?
    let goalId: String?
    let title: String
    let subject: String
    let startTime: String?
    let durationMinutes: Int
    let status: PlanItemStatus
    let rationale: String?
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case planId = "plan_id"
        case taskId = "task_id"
        case goalId = "goal_id"
        case title, subject
        case startTime = "start_time"
        case durationMinutes = "duration_minutes"
        case status, rationale
        case sortOrder = "sort_order"
    }
}

/// `/plan?date=` レスポンス。plan と items のセット。
struct PlanForDate: Codable, Hashable {
    let plan: StudyPlan?
    let items: [PlanItem]
}

/// `/plan/periods` の各 period + 中の日毎プラン。実 API のレスポンス:
/// `{ period, days: [{ plan, items }] }`
struct PeriodWithDays: Codable, Identifiable, Hashable {
    var id: String { period.id }
    let period: StudyPlanPeriod
    let days: [PlanForDate]

    /// UI で日付チップに使う yyyy-MM-dd の配列 (plan_date でソート済み)。
    var dateStrings: [String] {
        days.compactMap { $0.plan?.planDate }
    }
}

