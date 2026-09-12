import Foundation

struct NotificationPreferences: Codable, Hashable {
    let morningReminder: Bool?
    let morningReminderTime: String?
    let planReminders: Bool?
    let planReminderMinutes: Int?
    let eveningSummary: Bool?
    let eveningSummaryTime: String?
    let streakAlerts: Bool?
    let quietHoursStart: String?
    let quietHoursEnd: String?
    let meetingReminders: Bool?
    let meetingReminderMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case morningReminder = "morning_reminder"
        case morningReminderTime = "morning_reminder_time"
        case planReminders = "plan_reminders"
        case planReminderMinutes = "plan_reminder_minutes"
        case eveningSummary = "evening_summary"
        case eveningSummaryTime = "evening_summary_time"
        case streakAlerts = "streak_alerts"
        case quietHoursStart = "quiet_hours_start"
        case quietHoursEnd = "quiet_hours_end"
        case meetingReminders = "meeting_reminders"
        case meetingReminderMinutes = "meeting_reminder_minutes"
    }
}
