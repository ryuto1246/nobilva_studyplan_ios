import Foundation
import AuthenticationServices
import UIKit

/// パスキー (WebAuthn) ログインを ASAuthorizationController でラップ。
///
/// ## サーバとの往復
/// 1. `POST /api/v1/auth/mobile/passkey/login-options` → `options` + `challenge_token`
/// 2. iOS で `ASAuthorizationController` を assertion モードで開く
/// 3. 取得した assertion + `challenge_token` を
///    `POST /api/v1/auth/mobile/passkey/login-verify` に投げてセッション取得
///
/// **前提**: `Associated Domains` に `webcredentials:study-plan.nobilva.jp` が入っていること。
/// Team ID / エンタイトルメント未設定でボタン disabled にしているので、この API 動作は
/// Team ID 確定後にユーザーが有効化する。
final class PasskeyClient: NSObject {
    static let rpId = "studyplan.nobilva.jp"

    struct LoginOptionsResponse: Decodable {
        struct Options: Decodable {
            let challenge: String
            let rpId: String?
            let timeout: Int?
            let userVerification: String?
        }
        let options: Options
        let challenge_token: String
    }

    private var continuation: CheckedContinuation<PasskeyAssertion, Error>?

    struct PasskeyAssertion {
        let credentialId: String       // base64url
        let clientDataJSON: String     // base64url
        let authenticatorData: String  // base64url
        let signature: String          // base64url
        let userHandle: String?        // base64url
        let challengeToken: String
    }

    /// options + challenge_token を Server から取得して assertion を起こす。
    @MainActor
    func login(identifier: String?, api: APIClient) async throws -> PasskeyAssertion {
        struct Body: Encodable { let identifier: String? }
        let resp: LoginOptionsResponse = try await api.post(
            "/api/v1/auth/mobile/passkey/login-options",
            body: Body(identifier: identifier),
            authorized: false
        )

        guard let challengeData = Data(base64URLEncoded: resp.options.challenge) else {
            throw APIError.invalidResponse
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: resp.options.rpId ?? Self.rpId)
        let request = provider.createCredentialAssertionRequest(challenge: challengeData)
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            self.stashedToken = resp.challenge_token
            controller.performRequests()
        }
    }

    private var stashedToken: String = ""
}

extension PasskeyClient: ASAuthorizationControllerDelegate {
    func authorizationController(controller: ASAuthorizationController,
                                  didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let cred = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion else {
            continuation?.resume(throwing: APIError.invalidResponse)
            continuation = nil
            return
        }
        let assertion = PasskeyAssertion(
            credentialId: cred.credentialID.base64URLEncodedString(),
            clientDataJSON: cred.rawClientDataJSON.base64URLEncodedString(),
            authenticatorData: cred.rawAuthenticatorData.base64URLEncodedString(),
            signature: cred.signature.base64URLEncodedString(),
            userHandle: cred.userID?.base64URLEncodedString(),
            challengeToken: stashedToken
        )
        continuation?.resume(returning: assertion)
        continuation = nil
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension PasskeyClient: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - base64url helpers

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded input: String) {
        var s = input.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let pad = s.count % 4
        if pad != 0 { s.append(String(repeating: "=", count: 4 - pad)) }
        self.init(base64Encoded: s)
    }
}
