import Foundation

enum APIError: Error, LocalizedError {
    case network(URLError)
    case decoding(Error)
    case server(status: Int, code: String, message: String)
    case unauthorized
    case invalidResponse
    case notLoggedIn
    /// URLSession リクエストが SwiftUI .task のキャンセル等で中断された。
    /// ユーザーに見せる価値のあるエラーではないので errorDescription は nil。
    case cancelled

    var errorDescription: String? {
        switch self {
        case .cancelled: return nil
        case .network: return "インターネットに接続できませんでした。通信状況を確認してください。"
        case .decoding: return "データを読み込めませんでした。時間をおいてもう一度お試しください。"
        case .server(let status, _, let message):
            // サーバの日本語メッセージ (業務エラー) はそのまま、英語の内部向けメッセージ
            // (入力検証など) は生徒に見せず汎用文言にする。
            return Self.containsJapanese(message) ? message : Self.genericMessage(status: status)
        case .unauthorized: return "ログインの有効期限が切れました。もう一度ログインしてください。"
        case .invalidResponse: return "サーバから想定外の応答がありました。時間をおいてもう一度お試しください。"
        case .notLoggedIn: return "ログインが必要です"
        }
    }

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    var isNetwork: Bool {
        if case .network = self { return true }
        return false
    }

    var code: String? {
        if case .server(_, let code, _) = self { return code }
        return nil
    }

    private static func containsJapanese(_ s: String) -> Bool {
        s.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }

    private static func genericMessage(status: Int) -> String {
        switch status {
        case 400, 422: return "操作を完了できませんでした。入力内容を確認してください。"
        case 401, 403: return "この操作を行う権限がありません。"
        case 404: return "見つかりませんでした。すでに削除された可能性があります。"
        case 409: return "すでに登録されています。"
        case 410: return "有効期限が切れています。もう一度やり直してください。"
        case 429: return "操作が続いたため一時的に制限されています。少し待ってからお試しください。"
        default: return "サーバでエラーが発生しました。時間をおいてもう一度お試しください。"
        }
    }

    /// サーバが明示的に「もう認証しないでほしい」と返した終末的なエラーか。
    /// 4xx (400/401/403) はサーバの意図的な拒否 → Keychain 消してログアウト。
    /// 通信断や 5xx は「今回はダメだけど次回は動くかも」なので session 保持したまま
    /// リトライさせるべき。この区別を bootstrap と APIClient の 401 分岐で共用する。
    var isTerminalAuth: Bool {
        switch self {
        case .server(status: let s, _, _):
            return (400...403).contains(s)
        case .unauthorized:
            return true
        default:
            return false
        }
    }
}
