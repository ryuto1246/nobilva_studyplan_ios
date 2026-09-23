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
        case .network(let e): return "通信エラー: \(e.localizedDescription)"
        case .decoding: return "サーバ応答の解析に失敗しました"
        case .server(_, _, let message): return message
        case .unauthorized: return "セッションの有効期限が切れました。もう一度ログインしてください。"
        case .invalidResponse: return "サーバから不正な応答が返されました"
        case .notLoggedIn: return "ログインが必要です"
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
