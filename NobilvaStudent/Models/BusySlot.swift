import Foundation

enum BusySource: String, Codable { case individual, team }

struct BusySlot: Codable, Identifiable, Hashable {
    let id: String
    let studentId: String?
    let teamId: String?
    let teamName: String?
    let title: String
    let weekday: Int?
    let specificDate: String?
    let timeOfDay: TimeOfDay
    let notes: String?
    let createdBy: String?
    let createdAt: String?
    let source: BusySource
    let optedOut: Bool?

    var isWeekly: Bool { weekday != nil }
    var weekdayLabel: String {
        guard let w = weekday, (0..<7).contains(w) else { return "" }
        return ["日", "月", "火", "水", "木", "金", "土"][w] + "曜"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case studentId = "student_id"
        case teamId = "team_id"
        case teamName = "team_name"
        case title, weekday
        case specificDate = "specific_date"
        case timeOfDay = "time_of_day"
        case notes
        case createdBy = "created_by"
        case createdAt = "created_at"
        case source
        case optedOut = "opted_out"
    }
}
