import Foundation
import AuthenticationServices
import UIKit

/// パスキー登録 (WebAuthn registration) を ASAuthorizationController でラップ。
///
/// PasskeyClient は login (assertion) 専用。登録はステートマシンが別 (attestation
/// を扱う delegate 分岐) なので、混ぜずに独立クラスとして持つ。
///
/// ## 呼び出しパターン
/// 1. サーバから registration options (challenge + user.id + user.name) を取得
/// 2. iOS で `ASAuthorizationController` を registration モードで開く
/// 3. 取得した attestation を verify エンドポイントに送る
///
/// **前提**: `Associated Domains` に `webcredentials:studyplan.nobilva.jp` が
/// 入っていること。Team ID / entitlements 未設定時は system dialog が失敗する。
final class PasskeyRegistrationClient: NSObject {
    static let rpId = "studyplan.nobilva.jp"

    struct Attestation {
        let credentialId: String       // base64url
        let clientDataJSON: String     // base64url
        let attestationObject: String  // base64url
    }

    private var continuation: CheckedContinuation<Attestation, Error>?

    /// options を受け取り、system の登録フローを起動して attestation を返す。
    /// - Parameters:
    ///   - challenge: サーバから受け取った base64url チャレンジ
    ///   - userIdBase64URL: user.id を base64url した文字列 (WebAuthn 仕様)
    ///   - userName: ユーザー名 (login hint に使う)
    @MainActor
    func register(
        challenge: String,
        userIdBase64URL: String,
        userName: String
    ) async throws -> Attestation {
        guard let challengeData = Data(base64URLEncoded: challenge) else {
            throw APIError.invalidResponse
        }
        guard let userIdData = Data(base64URLEncoded: userIdBase64URL) else {
            throw APIError.invalidResponse
        }

        let provider = ASAuthorizationPlatformPublicKeyCredentialProvider(
            relyingPartyIdentifier: Self.rpId
        )
        let request = provider.createCredentialRegistrationRequest(
            challenge: challengeData,
            name: userName,
            userID: userIdData
        )
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            controller.performRequests()
        }
    }
}

extension PasskeyRegistrationClient: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let cred = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration else {
            continuation?.resume(throwing: APIError.invalidResponse)
            continuation = nil
            return
        }
        // attestationObject は登録時のみ返る。nil の場合はサーバ側で弾かれる。
        guard let attestation = cred.rawAttestationObject else {
            continuation?.resume(throwing: APIError.invalidResponse)
            continuation = nil
            return
        }
        let payload = Attestation(
            credentialId: cred.credentialID.base64URLEncodedString(),
            clientDataJSON: cred.rawClientDataJSON.base64URLEncodedString(),
            attestationObject: attestation.base64URLEncodedString()
        )
        continuation?.resume(returning: payload)
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension PasskeyRegistrationClient: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
