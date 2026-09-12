import Foundation
import SwiftUI

/// 認証状態を保持する ObservableObject。
/// - `accessToken` はメモリのみ、`refreshToken` は Keychain 永続化。
/// - `bootstrap()` を起動時に呼び、refresh_token があれば透過的にセッション復元。
/// - APIClient から `TokenProviding` として参照される。
@MainActor
final class AuthStore: ObservableObject, TokenProviding {

    // MARK: - Published UI state
    enum Phase {
        case bootstrapping    // 起動時、refresh を試す間
        case unauthenticated  // ログイン画面を表示
        case authenticated    // メイン画面を表示
    }

    @Published private(set) var phase: Phase = .bootstrapping
    @Published private(set) var currentUser: SessionUser?
    @Published private(set) var currentRole: String?

    // MARK: - Tokens
    // 複数タスクから同時に読まれる可能性があるが、set は refreshの完了時のみ。
    // 一時的な同時読み書きはアプリの動作に影響しないので nonisolated(unsafe) で許容。
    nonisolated(unsafe) private var _accessToken: String?
    nonisolated var accessToken: String? { _accessToken }

    let api: APIClient

    private let refreshKey = "refresh_token"

    init(api: APIClient = APIClient()) {
        self.api = api
        // nonisolated setter なので同期で確実に紐付けする。
        api.setTokenProvider(self)
        // Push 通知の APNs トークンをサーバに登録するために APIClient を渡す。
        // 未ログイン時に registerDeviceToken が来た場合は PushService 側で
        // pendingTokenHex に保持され、attach 済みなら即送信される。
        PushService.shared.attach(api: api)
    }

    // MARK: - Bootstrap

    /// アプリ起動時に呼ぶ。refresh_token が Keychain にあれば試す。
    func bootstrap() async {
        phase = .bootstrapping
        guard Keychain.get(refreshKey) != nil else {
            phase = .unauthenticated
            return
        }
        do {
            try await refreshTokens()
            phase = .authenticated
        } catch {
            Log.auth.error("bootstrap refresh failed: \(String(describing: error))")
            Keychain.delete(refreshKey)
            _accessToken = nil
            phase = .unauthenticated
        }
    }

    // MARK: - Login

    struct PasswordLoginBody: Encodable {
        let identifier: String
        let password: String
    }

    func loginWithPassword(identifier: String, password: String) async throws {
        let body = PasswordLoginBody(identifier: identifier, password: password)
        let resp: MobileSessionResponse = try await api.post(
            "/api/v1/auth/mobile/session",
            body: body,
            authorized: false
        )
        RememberedIdentity.save(identifier: identifier)
        adopt(session: resp.session, role: resp.profile?.role)
        phase = .authenticated
    }

    /// パスキー assertion 検証後に呼ぶ (Passkey フロー内部から)。
    func adoptPasskeySession(_ resp: MobileSessionResponse) {
        adopt(session: resp.session, role: resp.profile?.role)
        phase = .authenticated
    }

    struct PasskeyVerifyBody: Encodable {
        struct Assertion: Encodable {
            let credentialId: String
            let clientDataJSON: String
            let authenticatorData: String
            let signature: String
            let userHandle: String?
        }
        let assertion: Assertion
        let challenge_token: String
    }

    // MARK: - Recovery (Magic Link 相当)

    struct RecoveryBody: Encodable {
        let email: String
    }
    struct RecoveryResponse: Decodable {
        let ok: Bool
        let note: String?
    }

    /// メールに「パスキー / パスワードを設定するためのリンク」を送信する。
    /// 初回ログインでパスキーもパスワードも設定していないユーザーはここから始める。
    /// - 呼び出しに Bearer 認証は不要 (recovery endpoint 側で email 一致を見る)。
    /// - サーバはアカウント有無を漏らさないため常に成功レスポンスを返す。
    nonisolated func requestRecoveryEmail(_ email: String) async throws -> String {
        let resp: RecoveryResponse = try await api.post(
            "/api/v1/auth/recovery/request",
            body: RecoveryBody(email: email),
            authorized: false
        )
        return resp.note ?? "指定のメールアドレスに登録があれば案内をお送りしました"
    }

    func loginWithPasskey(identifier: String?) async throws {
        let client = PasskeyClient()
        let assertion = try await client.login(identifier: identifier, api: api)
        let body = PasskeyVerifyBody(
            assertion: .init(
                credentialId: assertion.credentialId,
                clientDataJSON: assertion.clientDataJSON,
                authenticatorData: assertion.authenticatorData,
                signature: assertion.signature,
                userHandle: assertion.userHandle
            ),
            challenge_token: assertion.challengeToken
        )
        let resp: MobileSessionResponse = try await api.post(
            "/api/v1/auth/mobile/passkey/login-verify",
            body: body,
            authorized: false
        )
        // identifier が空 (自動探索) の場合、user.email が返っていれば覚えておく。
        // 通常は ClaimView / 前回ログインで既に保存されているはず。
        if let id = identifier?.trimmingCharacters(in: .whitespaces), !id.isEmpty {
            RememberedIdentity.save(identifier: id)
        } else if let email = resp.session.user.email {
            RememberedIdentity.save(identifier: email)
        }
        adopt(session: resp.session, role: resp.profile?.role)
        phase = .authenticated
    }

    // MARK: - Claim (deep link from invitation email)

    struct ClaimTokenPreview: Decodable {
        let studentEmail: String
        let studentDisplayName: String
        let studentGradeLevel: String
        let expiresAt: String

        enum CodingKeys: String, CodingKey {
            case studentEmail = "student_email"
            case studentDisplayName = "student_display_name"
            case studentGradeLevel = "student_grade_level"
            case expiresAt = "expires_at"
        }
    }

    struct ClaimVerifyBody: Encodable {
        let claim_token: String
    }

    /// claim トークン (招待メールのリンクから抽出) の有効性を確認して、
    /// 表示用の生徒情報を返す。まだユーザーは作られない。
    nonisolated func fetchClaimPreview(token: String) async throws -> ClaimTokenPreview {
        try await api.post(
            "/api/v1/auth/mobile/claim/verify",
            body: ClaimVerifyBody(claim_token: token),
            authorized: false
        )
    }

    struct ClaimPasskeyOptionsBody: Encodable {
        let claim_token: String
    }
    struct ClaimPasskeyOptionsResponse: Decodable {
        struct Options: Decodable {
            struct User: Decodable {
                let id: String
                let name: String
                let displayName: String
            }
            let challenge: String
            let user: User
        }
        let options: Options
    }

    struct ClaimBody: Encodable {
        struct PasskeyResponse: Encodable {
            let id: String
            let rawId: String
            let type: String
            let response: Response
            struct Response: Encodable {
                let clientDataJSON: String
                let attestationObject: String
            }
        }
        let auth_method: String
        let claim_token: String
        let username: String
        // password 認証時のみ
        let password: String?
        // passkey 認証時のみ
        let passkey_response: PasskeyResponse?
        let passkey_device_name: String?
    }

    /// パスキー方式で claim を実行。register options 取得 → system 登録 UI →
    /// verify を1トランザクションで完了させる。
    func claimWithPasskey(token: String, username: String) async throws {
        let optionsResp: ClaimPasskeyOptionsResponse = try await api.post(
            "/api/v1/auth/mobile/claim/passkey-options",
            body: ClaimPasskeyOptionsBody(claim_token: token),
            authorized: false
        )
        let opts = optionsResp.options
        let client = PasskeyRegistrationClient()
        let attestation = try await client.register(
            challenge: opts.challenge,
            userIdBase64URL: opts.user.id,
            userName: opts.user.name
        )
        let body = ClaimBody(
            auth_method: "passkey",
            claim_token: token,
            username: username,
            password: nil,
            passkey_response: .init(
                id: attestation.credentialId,
                rawId: attestation.credentialId,
                type: "public-key",
                response: .init(
                    clientDataJSON: attestation.clientDataJSON,
                    attestationObject: attestation.attestationObject
                )
            ),
            passkey_device_name: UIDevice.current.name
        )
        let resp: MobileSessionResponse = try await api.post(
            "/api/v1/auth/mobile/claim",
            body: body,
            authorized: false
        )
        RememberedIdentity.save(identifier: username)
        adopt(session: resp.session, role: resp.profile?.role)
        phase = .authenticated
    }

    /// パスワード方式で claim (fallback: パスキー登録に失敗した場合のみ)。
    func claimWithPassword(token: String, username: String, password: String) async throws {
        let body = ClaimBody(
            auth_method: "password",
            claim_token: token,
            username: username,
            password: password,
            passkey_response: nil,
            passkey_device_name: nil
        )
        let resp: MobileSessionResponse = try await api.post(
            "/api/v1/auth/mobile/claim",
            body: body,
            authorized: false
        )
        RememberedIdentity.save(identifier: username)
        adopt(session: resp.session, role: resp.profile?.role)
        phase = .authenticated
    }

    // MARK: - Recovery consume (deep link from recovery email)

    struct RecoveryVerifyBody: Encodable {
        let token: String
    }

    /// 保護者メールのリカバリトークンを消費してセッションを確立。
    /// この後はユーザーを PasskeyManagementView に案内して再登録させる。
    func consumeRecoveryToken(_ token: String) async throws {
        let body = RecoveryVerifyBody(token: token)
        let resp: MobileSessionResponse = try await api.post(
            "/api/v1/auth/mobile/recovery/verify",
            body: body,
            authorized: false
        )
        adopt(session: resp.session, role: resp.profile?.role)
        phase = .authenticated
    }

    // MARK: - Security operations (authenticated)

    struct AddPasskeyOptionsResponse: Decodable {
        struct Options: Decodable {
            struct User: Decodable {
                let id: String
                let name: String
                let displayName: String
            }
            let challenge: String
            let user: User
        }
        let options: Options
        let challenge_token: String
    }

    struct AddPasskeyVerifyBody: Encodable {
        struct Registration: Encodable {
            let id: String
            let rawId: String
            let type: String
            let response: Response
            struct Response: Encodable {
                let clientDataJSON: String
                let attestationObject: String
            }
        }
        let registration: Registration
        let challenge_token: String
        let device_name: String?
    }

    /// ログイン中のアカウントにパスキーを追加登録する。
    func addPasskey() async throws {
        let optionsResp: AddPasskeyOptionsResponse = try await api.postVoid(
            "/api/v1/auth/mobile/security/passkey-options"
        )
        let opts = optionsResp.options
        let client = PasskeyRegistrationClient()
        let attestation = try await client.register(
            challenge: opts.challenge,
            userIdBase64URL: opts.user.id,
            userName: opts.user.name
        )
        let body = AddPasskeyVerifyBody(
            registration: .init(
                id: attestation.credentialId,
                rawId: attestation.credentialId,
                type: "public-key",
                response: .init(
                    clientDataJSON: attestation.clientDataJSON,
                    attestationObject: attestation.attestationObject
                )
            ),
            challenge_token: optionsResp.challenge_token,
            device_name: UIDevice.current.name
        )
        let _: EmptyResponse = try await api.post(
            "/api/v1/auth/mobile/security/passkey-verify",
            body: body
        )
    }

    struct PasswordChangeBody: Encodable {
        let new_password: String
    }

    /// パスワードを設定 or 変更。副作用で profiles.password_enabled=TRUE になる。
    func setOrChangePassword(_ newPassword: String) async throws {
        let _: EmptyResponse = try await api.post(
            "/api/v1/auth/mobile/security/password",
            body: PasswordChangeBody(new_password: newPassword)
        )
    }

    // MARK: - Refresh (TokenProviding)

    struct RefreshBody: Encodable {
        let refresh_token: String
    }

    nonisolated func refreshTokens() async throws {
        guard let stored = Keychain.get(refreshKey) else {
            throw APIError.unauthorized
        }
        let body = RefreshBody(refresh_token: stored)
        let resp: MobileSessionRefreshResponse = try await api.post(
            "/api/v1/auth/mobile/session/refresh",
            body: body,
            authorized: false
        )
        await MainActor.run { [self] in
            self._accessToken = resp.session.accessToken
            Keychain.set(resp.session.refreshToken, key: refreshKey)
            self.currentUser = resp.session.user
        }
    }

    // MARK: - Logout

    func logout() async {
        // 別ユーザーで再ログインしたときに前ユーザーの端末へ push が飛ばないよう、
        // サーバ側の APNs トークン行を先に消してからセッション破棄する。
        await PushService.shared.unregisterOnSignOut()
        // best-effort でサーバに DELETE。失敗しても続行。
        do {
            let _: EmptyResponse = try await api.delete("/api/v1/auth/mobile/session")
        } catch {
            Log.auth.warning("server logout failed (ignored): \(String(describing: error))")
        }
        await clearForLogout()
    }

    nonisolated func clearForLogout() async {
        await MainActor.run { [self] in
            _accessToken = nil
            Keychain.delete(refreshKey)
            currentUser = nil
            currentRole = nil
            // 別ユーザーが同じ端末でログインする可能性を考慮し、キャッシュも全消去。
            DiskCache.clearAll()
            phase = .unauthenticated
        }
    }

    // MARK: - Private

    private func adopt(session: MobileSession, role: String?) {
        _accessToken = session.accessToken
        Keychain.set(session.refreshToken, key: refreshKey)
        currentUser = session.user
        currentRole = role
    }
}
