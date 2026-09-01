import Foundation

/// サーバ側の ChatThreadSummary。lib/actions/chat.ts で camelCase JSON を返す
/// (通常の DB 由来 snake_case とは違う) ので CodingKeys は不要。
struct ChatThread: Codable, Identifiable, Hashable {
    let id: String
    let teacherId: String?
    let teacherName: String?
    let studentId: String?
    let studentName: String?
    let lastMessageAt: String?
    let lastMessageBody: String?
    let unreadCount: Int?
}

/// サーバ側は `{ teacherId, displayName }` (camelCase) を返す — dashboard/summary と
/// /chat/partners の両方で同じ shape。unreadCount は現状ペイロードに含まれないが将来用に optional。
struct ChatPartner: Codable, Identifiable, Hashable {
    let teacherId: String
    let displayName: String
    let unreadCount: Int?

    var id: String { teacherId }
}

/// サーバ側の ChatMessage も camelCase。
struct ChatMessage: Codable, Identifiable, Hashable {
    let id: String
    let threadId: String?
    let senderId: String?
    let senderName: String?
    let body: String?
    let imageUrl: String?
    let isAdminMessage: Bool?
    let createdAt: String
}

/// POST /chat/threads の返り値は明示的 snake_case (`{ thread_id }`)。
struct ChatThreadCreatedResponse: Codable {
    let threadId: String
    enum CodingKeys: String, CodingKey { case threadId = "thread_id" }
}

/// POST /chat/{id}/messages(/image) の返り値も snake_case (`{ message_id, image_url }`)。
struct ChatMessageCreatedResponse: Codable {
    let messageId: String
    let imageUrl: String?
    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case imageUrl = "image_url"
    }
}

struct ChatUnreadTotalResponse: Codable {
    let total: Int
}
