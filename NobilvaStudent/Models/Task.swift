import Foundation

enum TaskStatus: String, Codable, CaseIterable, Identifiable {
    case pending, inProgress = "in_progress", completed, skipped
    var id: String { rawValue }
    var label: String {
        switch self {
        case .pending: return "未着手"
        case .inProgress: return "取り組み中"
        case .completed: return "完了"
        case .skipped: return "スキップ"
        }
    }
    var systemImage: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "play.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "forward.end.circle.fill"
        }
    }

    /// 知らない値 (サーバーに後から足された状態) は未着手として読む。一覧ごと読めなくなるのを防ぐ。
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TaskStatus(rawValue: raw) ?? .pending
    }
}

enum TaskRecurrence: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return "一度だけ"
        case .daily: return "毎日"
        case .weekly: return "毎週"
        }
    }
}

enum TimeOfDay: String, Codable, CaseIterable, Identifiable {
    case morning, afternoon, evening
    var id: String { rawValue }
    var label: String {
        switch self {
        case .morning: return "朝"
        case .afternoon: return "昼"
        case .evening: return "夜"
        }
    }
}

struct StudentTask: Codable, Identifiable, Hashable {
    let id: String
    let studentId: String
    let title: String
    let subject: String
    let estimatedMinutes: Int
    let status: TaskStatus
    let dueDate: String?
    let scheduledDate: String?
    let unitCount: Int?
    let unitLabel: String?
    let goalId: String?
    let recurrence: TaskRecurrence
    let recurrenceWeekday: Int?
    let preferredTimeOfDay: TimeOfDay?
    let notes: String?
    let createdAt: String?
    /// status が skipped のときに生徒が選んだ理由 (任意)。
    var skipReason: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case studentId = "student_id"
        case title, subject
        case estimatedMinutes = "estimated_minutes"
        case status
        case dueDate = "due_date"
        case scheduledDate = "scheduled_date"
        case unitCount = "unit_count"
        case unitLabel = "unit_label"
        case goalId = "goal_id"
        case recurrence
        case recurrenceWeekday = "recurrence_weekday"
        case preferredTimeOfDay = "preferred_time_of_day"
        case notes
        case createdAt = "created_at"
        case skipReason = "skip_reason"
    }
}
