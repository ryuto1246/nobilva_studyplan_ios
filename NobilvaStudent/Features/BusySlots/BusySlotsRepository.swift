import Foundation

struct BusySlotsRepository {
    let api: APIClient

    func list() async throws -> [BusySlot] {
        try await api.get("/api/v1/student/busy-slots")
    }

    struct CreateBody: Encodable {
        let title: String
        let kind: String        // "weekly" or "once"
        let weekday: Int?
        let specific_date: String?
        let time_of_day: String
        let notes: String?
    }

    func create(_ body: CreateBody) async throws {
        let _: EmptyResponse = try await api.post("/api/v1/student/busy-slots", body: body)
    }

    func delete(_ id: String) async throws {
        let _: EmptyResponse = try await api.delete("/api/v1/student/busy-slots/\(id)")
    }

    struct OptOutBody: Encodable { let opt_out: Bool }
    func teamEventOptOut(_ id: String, optOut: Bool) async throws {
        let _: EmptyResponse = try await api.post("/api/v1/student/team-events/\(id)/opt-out", body: OptOutBody(opt_out: optOut))
    }
}
