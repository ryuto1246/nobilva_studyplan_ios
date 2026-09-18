import Foundation

struct MeetingsRepository {
    let api: APIClient

    func list(includePast: Bool = false) async throws -> [Meeting] {
        let list: [Meeting] = try await api.get(
            "/api/v1/student/meetings",
            query: ["includePast": includePast ? "true" : "false"]
        )
        DiskCache.write(list, key: includePast ? .meetingsWithPast : .meetings)
        return list
    }

    static func cachedList(includePast: Bool) -> [Meeting]? {
        DiskCache.read([Meeting].self, key: includePast ? .meetingsWithPast : .meetings)
    }

    func upcoming() async throws -> Meeting? {
        try await api.get("/api/v1/student/meetings/upcoming")
    }

    func detail(_ id: String) async throws -> Meeting {
        try await api.get("/api/v1/student/meetings/\(id)")
    }

    struct NoteBody: Encodable { let note: String? }

    func cancel(_ id: String, note: String?) async throws {
        let _: EmptyResponse = try await api.post("/api/v1/student/meetings/\(id)/cancel", body: NoteBody(note: note))
    }

    func requestReschedule(_ id: String, note: String?) async throws {
        let _: EmptyResponse = try await api.post("/api/v1/student/meetings/\(id)/reschedule-request", body: NoteBody(note: note))
    }

    struct ProposalBody: Encodable {
        let proposed_start: String
        let duration_minutes: Int
        let note: String?
    }

    func proposeReschedule(_ id: String, start: Date, durationMinutes: Int, note: String?) async throws {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let _: EmptyResponse = try await api.post(
            "/api/v1/student/meetings/\(id)/proposal",
            body: ProposalBody(proposed_start: iso.string(from: start),
                               duration_minutes: durationMinutes, note: note)
        )
    }

    func acceptProposal(_ id: String) async throws {
        let _: EmptyResponse = try await api.postVoid("/api/v1/student/meetings/\(id)/proposal/accept")
    }

    func rejectProposal(_ id: String, note: String?) async throws {
        let _: EmptyResponse = try await api.post("/api/v1/student/meetings/\(id)/proposal/reject", body: NoteBody(note: note))
    }

    /// 自分が出したリスケ希望 / 提案を取り下げて state を "none" に戻す。
    /// 相手が出したものは (student 権限では) 取り下げ不可 — サーバ側で 400 返す。
    func withdrawReschedule(_ id: String) async throws {
        let _: EmptyResponse = try await api.postVoid("/api/v1/student/meetings/\(id)/reschedule-request/withdraw")
    }
}
