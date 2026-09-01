import Foundation

enum SessionMode: String, Codable, CaseIterable, Identifiable {
    case timer, pomodoro, stopwatch, manual
    var id: String { rawValue }
    var label: String {
        switch self {
        case .timer: return "タイマー"
        case .pomodoro: return "ポモドーロ"
        case .stopwatch: return "ストップウォッチ"
        case .manual: return "手動記録"
        }
    }
}

struct StudySession: Codable, Identifiable, Hashable {
    let id: String
    let studentId: String
    let planItemId: String?
    let startedAt: String
    let endedAt: String?
    let durationSeconds: Int
    let mode: SessionMode

    enum CodingKeys: String, CodingKey {
        case id
        case studentId = "student_id"
        case planItemId = "plan_item_id"
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSeconds = "duration_seconds"
        case mode
    }
}

struct SessionStartResponse: Codable {
    let sessionId: String
    enum CodingKeys: String, CodingKey { case sessionId = "session_id" }
}

/// セッション完了 API のレスポンス。旧仕様は xp_gain を返していたが、
/// XP 機能を UI で使わないため無視する。デコードに失敗しないよう空の struct。
struct SessionCompletedResponse: Codable {}
