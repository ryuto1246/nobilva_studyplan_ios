import Foundation

enum MeetingStatus: String, Codable { case scheduled, cancelled, completed }
enum RescheduleState: String, Codable { case none, requested, proposed }

struct MeetingParty: Codable, Hashable {
    let id: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
    }
}

struct Meeting: Codable, Identifiable, Hashable {
    let id: String
    let seriesId: String?
    let teacherId: String?
    let studentId: String?
    let createdBy: String?
    let title: String
    let meetingUrl: String?
    let notes: String?
    let scheduledStartAt: String
    let scheduledEndAt: String
    let status: MeetingStatus
    let rescheduleState: RescheduleState
    let rescheduleActor: String?
    let rescheduleNote: String?
    let proposedStartAt: String?
    let proposedEndAt: String?
    let teacher: MeetingParty?
    let student: MeetingParty?

    var isPast: Bool {
        guard let end = JSTDate.parseTimestamp(scheduledEndAt) else { return false }
        if status == .cancelled { return false }
        return end < Date()
    }

    /// 完了済みも「終わったもの」として扱う (終了時刻が未来でも)。
    var isFinished: Bool { status == .completed || isPast }
    var isUpcoming: Bool { status == .scheduled && !isFinished }

    var displayStatus: (label: String, tint: String) {
        if status == .cancelled { return ("キャンセル", "gray") }
        if isFinished { return ("終了", "gray") }
        if rescheduleState == .proposed { return ("日程の提案あり", "orange") }
        if rescheduleState == .requested { return ("日程変更の希望あり", "orange") }
        return ("予定", "blue")
    }

    var startDate: Date? { JSTDate.parseTimestamp(scheduledStartAt) }

    /// 開始日が今日 (JST) か。
    var isToday: Bool {
        guard let start = startDate else { return false }
        return JSTDate.calendar.isDate(start, inSameDayAs: Date())
    }

    /// "10月31日(土) 19:00"
    var scheduleLabel: String {
        guard let start = startDate else { return "" }
        return JSTDate.displayMonthDay.string(from: start) + " " + JSTDate.time.string(from: start)
    }

    /// Web `lib/meetings/format.ts` 相当の「あと N 日 / 時間 / 分」。
    var countdownLabel: String? {
        guard isUpcoming, let start = startDate else { return nil }
        let seconds = start.timeIntervalSinceNow
        if seconds <= 0 { return "開始時刻です" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "あと\(max(1, minutes))分" }
        let hours = minutes / 60
        if hours < 24 { return "あと\(hours)時間" }
        return "あと\(hours / 24)日"
    }

    var joinURL: URL? {
        guard isUpcoming, let s = meetingUrl, !s.isEmpty else { return nil }
        return URL(string: s)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case seriesId = "series_id"
        case teacherId = "teacher_id"
        case studentId = "student_id"
        case createdBy = "created_by"
        case title
        case meetingUrl = "meeting_url"
        case notes
        case scheduledStartAt = "scheduled_start_at"
        case scheduledEndAt = "scheduled_end_at"
        case status
        case rescheduleState = "reschedule_state"
        case rescheduleActor = "reschedule_actor"
        case rescheduleNote = "reschedule_note"
        case proposedStartAt = "proposed_start_at"
        case proposedEndAt = "proposed_end_at"
        case teacher, student
    }
}
