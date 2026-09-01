import Foundation

struct PlanRepository {
    let api: APIClient

    func fetchPeriods() async throws -> [PeriodWithDays] {
        let list: [PeriodWithDays] = try await api.get("/api/v1/student/plan/periods")
        DiskCache.write(list, key: .periods)
        return list
    }

    static func cachedPeriods() -> [PeriodWithDays]? {
        DiskCache.read([PeriodWithDays].self, key: .periods)
    }

    func fetchDay(_ date: String) async throws -> PlanForDate {
        try await api.get("/api/v1/student/plan", query: ["date": date])
    }

    struct StatusBody: Encodable { let status: String }

    func setItemStatus(_ id: String, status: PlanItemStatus) async throws {
        let _: EmptyResponse = try await api.patch(
            "/api/v1/student/plan/items/\(id)/status",
            body: StatusBody(status: status.rawValue)
        )
    }
}
