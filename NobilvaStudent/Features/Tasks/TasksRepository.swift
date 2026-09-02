import Foundation

struct TasksRepository {
    let api: APIClient

    /// scheduled_date が null かつ、まだどの日別プランにも拾われていないタスク。
    /// Web の getUnscheduledTasksForStudent と同じフィルタを API 側で適用済み
    /// なので、クライアントで scheduled_date を再判定する必要はない。
    func listUnscheduled() async throws -> [StudentTask] {
        let list: [StudentTask] = try await api.get("/api/v1/student/tasks/unscheduled")
        DiskCache.write(list, key: .unscheduledTasks)
        return list
    }

    static func cachedUnscheduled() -> [StudentTask]? {
        DiskCache.read([StudentTask].self, key: .unscheduledTasks)
    }

    func overdue() async throws -> [StudentTask] {
        try await api.get("/api/v1/student/tasks/overdue")
    }

    struct TaskBody: Encodable {
        var title: String
        var subject: String?
        var dueDate: String?
        var estimatedMinutes: Int?
        var unitCount: Int?
        var unitLabel: String?
        var goalId: String?
        var recurrence: String?
        var preferredTimeOfDay: String?
        var scheduledDate: String?
        var notes: String?
        var recurrenceWeekday: Int?
    }

    struct CreateResponse: Codable {
        let id: String
    }

    func create(_ body: TaskBody) async throws -> CreateResponse {
        try await api.post("/api/v1/student/tasks", body: body)
    }

    func update(_ id: String, body: TaskBody) async throws {
        let _: EmptyResponse = try await api.patch("/api/v1/student/tasks/\(id)", body: body)
    }

    struct StatusBody: Encodable { let status: String }

    func setStatus(_ id: String, status: TaskStatus) async throws {
        let _: EmptyResponse = try await api.patch("/api/v1/student/tasks/\(id)/status", body: StatusBody(status: status.rawValue))
    }

    func delete(_ id: String) async throws {
        let _: EmptyResponse = try await api.delete("/api/v1/student/tasks/\(id)")
    }

    func duplicate(_ id: String) async throws {
        let _: EmptyResponse = try await api.postVoid("/api/v1/student/tasks/\(id)/duplicate")
    }
}
