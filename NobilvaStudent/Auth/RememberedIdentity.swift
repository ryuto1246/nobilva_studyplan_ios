import Foundation

/// 前回ログインした identifier (ユーザーID or メール) と表示名を UserDefaults に
/// 覚えておき、次回起動時のログイン画面で「○○ さんとしてログイン」の表示に使う。
///
/// Keychain ではなく UserDefaults なのは意図的:
///   - 機密情報ではない (パスキー or パスワードで守られる)
///   - プレ認証状態 (bootstrap 失敗時) でも読める必要がある
///   - 子供の端末は自分のもの前提なので、他人に見える心配は薄い
///
/// ログアウトでは消さない。「違うアカウントで入る」ボタンから明示的に `forget()`。
enum RememberedIdentity {
    private static let identifierKey = "nobilva.remembered.identifier"
    private static let displayNameKey = "nobilva.remembered.displayName"

    struct Snapshot: Equatable {
        let identifier: String
        let displayName: String?
    }

    static func read() -> Snapshot? {
        let defaults = UserDefaults.standard
        guard let identifier = defaults.string(forKey: identifierKey),
              !identifier.isEmpty else { return nil }
        return Snapshot(
            identifier: identifier,
            displayName: defaults.string(forKey: displayNameKey)
        )
    }

    static func save(identifier: String, displayName: String? = nil) {
        let defaults = UserDefaults.standard
        defaults.set(identifier, forKey: identifierKey)
        if let displayName, !displayName.isEmpty {
            defaults.set(displayName, forKey: displayNameKey)
        }
    }

    /// identifier は残したまま、後から取得した displayName を追記/更新するとき用。
    static func updateDisplayName(_ displayName: String) {
        guard !displayName.isEmpty else { return }
        UserDefaults.standard.set(displayName, forKey: displayNameKey)
    }

    static func forget() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: identifierKey)
        defaults.removeObject(forKey: displayNameKey)
    }
}
