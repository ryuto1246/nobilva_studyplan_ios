import Foundation

/// サーバは常に `{ data: T }` または `{ error: { code, message } }` を返す。
struct Envelope<T: Decodable>: Decodable {
    let data: T?
    let error: APIErrorPayload?
}

struct APIErrorPayload: Decodable {
    let code: String
    let message: String
}

struct EmptyResponse: Decodable {}
