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

    var displayStatus: (label: String, tint: String) {
        if status == .cancelled { return ("キャンセル", "gray") }
        if isPast { return ("終了", "gray") }
        if rescheduleState == .proposed { return ("リスケ提案中", "orange") }
        if rescheduleState == .requested { return ("リスケ希望", "orange") }
        return ("予定", "blue")
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
