import Foundation

/// `/auth/mobile/session` レスポンスの `session` 部分。
struct MobileSession: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let expiresAt: Int
    let user: SessionUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case user
    }
}

struct SessionUser: Decodable {
    let id: String
    let email: String?
}

/// `/auth/mobile/session` レスポンスの `profile` 部分。
struct SessionProfile: Decodable {
    let role: String
    let homePath: String?

    enum CodingKeys: String, CodingKey {
        case role
        case homePath = "home_path"
    }
}

struct MobileSessionResponse: Decodable {
    let session: MobileSession
    let profile: SessionProfile?
}

struct MobileSessionRefreshResponse: Decodable {
    let session: MobileSession
}
