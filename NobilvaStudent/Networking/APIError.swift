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
}
