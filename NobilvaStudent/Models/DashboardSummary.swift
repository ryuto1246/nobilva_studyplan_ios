import Foundation

/// `/api/v1/student/dashboard/summary` の全レスポンス。
/// 1 リクエストでホーム画面が必要な 7 種類のデータを取ってくる。
struct DashboardSummary: Codable {
    let profile: DashboardProfile?
    let today: DashboardDay?
    let tomorrow: DashboardDay?
    let overdueTasks: [StudentTask]
    let chatPartners: [ChatPartner]
    let busySlots: [BusySlot]
    let upcomingMeeting: Meeting?

    enum CodingKeys: String, CodingKey {
        case profile, today, tomorrow
        case overdueTasks = "overdue_tasks"
        case chatPartners = "chat_partners"
        case busySlots = "busy_slots"
        case upcomingMeeting = "upcoming_meeting"
    }
}

/// dashboard/summary の profile はミニマム表示用の subset。
struct DashboardProfile: Codable {
    let displayName: String?
    let aiPlanEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case aiPlanEnabled = "ai_plan_enabled"
    }
}

/// dashboard/summary の today / tomorrow に入る 1 日分のプラン (nullable)。
struct DashboardDay: Codable {
    let date: String
    let plan: PlanForDate?
}
