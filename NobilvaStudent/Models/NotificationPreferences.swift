import Foundation

/// `notification_preferences` 行。GET は DB の行をそのまま (snake_case) 返す。
/// サーバに保存先があるのはこの 3 項目だけ。
struct NotificationPreferences: Codable, Hashable {
    var chatNotifications: Bool?
    var meetingReminders: Bool?
    var meetingReminderMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case chatNotifications = "chat_notifications"
        case meetingReminders = "meeting_reminders"
        case meetingReminderMinutes = "meeting_reminder_minutes"
    }

    static let defaults = NotificationPreferences(
        chatNotifications: false, meetingReminders: true, meetingReminderMinutes: 30
    )
}
