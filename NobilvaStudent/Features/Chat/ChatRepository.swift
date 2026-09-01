import Foundation

struct ChatRepository {
    let api: APIClient

    func threads() async throws -> [ChatThread] {
        let list: [ChatThread] = try await api.get("/api/v1/student/chat/threads")
        DiskCache.write(list, key: .chatThreads)
        return list
    }

    func partners() async throws -> [ChatPartner] {
        let list: [ChatPartner] = try await api.get("/api/v1/student/chat/partners")
        DiskCache.write(list, key: .chatPartners)
        return list
    }

    static func cachedThreads() -> [ChatThread]? {
        DiskCache.read([ChatThread].self, key: .chatThreads)
    }
    static func cachedPartners() -> [ChatPartner]? {
        DiskCache.read([ChatPartner].self, key: .chatPartners)
    }

    func unreadTotal() async throws -> Int {
        let r: ChatUnreadTotalResponse = try await api.get("/api/v1/student/chat/unread/total")
        return r.total
    }

    func messages(threadId: String) async throws -> [ChatMessage] {
        try await api.get("/api/v1/student/chat/\(threadId)/messages")
    }

    struct StartThreadBody: Encodable {
        let teacher_id: String?
    }

    func createOrGetThread(teacherId: String?) async throws -> ChatThreadCreatedResponse {
        try await api.post("/api/v1/student/chat/threads", body: StartThreadBody(teacher_id: teacherId))
    }

    struct SendBody: Encodable { let body: String }

    func send(threadId: String, body: String) async throws -> ChatMessageCreatedResponse {
        try await api.post("/api/v1/student/chat/\(threadId)/messages", body: SendBody(body: body))
    }

    struct SendImageBody: Encodable {
        let image_base64: String
        let content_type: String
        let caption: String?
    }

    func sendImage(threadId: String, imageData: Data, contentType: String, caption: String?) async throws -> ChatMessageCreatedResponse {
        let base64 = imageData.base64EncodedString()
        return try await api.post(
            "/api/v1/student/chat/\(threadId)/messages/image",
            body: SendImageBody(image_base64: base64, content_type: contentType, caption: caption)
        )
    }

    func markRead(threadId: String) async throws {
        let _: EmptyResponse = try await api.postVoid("/api/v1/student/chat/\(threadId)/read")
    }
}
