import Foundation

/// 単一の URLSession ベース HTTP クライアント。
/// - Bearer JWT の差し込み
/// - 401 → refresh → retry (once) の自動リカバリ
/// - `{ data }`/`{ error }` エンベロープの剥がし
///
/// 循環依存を避けるため、Auth への参照は `TokenProviding` プロトコル経由。
protocol TokenProviding: AnyObject {
    var accessToken: String? { get }
    func refreshTokens() async throws
    func clearForLogout() async
}

actor APIClient {
    static let baseURL = URL(string: "https://studyplan.nobilva.jp")!

    private let session: URLSession
    // tokenProvider は weak ref 単体なので actor 外から同期で set できるように。
    // (actor の setTokenProvider を Task で呼ぶと login より遅くなり、
    //  ログイン直後の別 View のリクエストで tokenProvider=nil → "ログインが必要です" になる。)
    nonisolated(unsafe) private weak var _tokenProvider: TokenProviding?
    nonisolated var tokenProvider: TokenProviding? { _tokenProvider }
    nonisolated func setTokenProvider(_ provider: TokenProviding) {
        self._tokenProvider = provider
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Public request helpers

    /// GET → T
    func get<T: Decodable>(_ path: String, query: [String: String] = [:], authorized: Bool = true) async throws -> T {
        try await request(path: path, method: "GET", query: query, body: Optional<EmptyEncodable>.none, authorized: authorized)
    }

    /// POST body → T
    func post<Body: Encodable, T: Decodable>(_ path: String, body: Body, authorized: Bool = true) async throws -> T {
        try await request(path: path, method: "POST", query: [:], body: body, authorized: authorized)
    }

    /// PATCH body → T
    func patch<Body: Encodable, T: Decodable>(_ path: String, body: Body, authorized: Bool = true) async throws -> T {
        try await request(path: path, method: "PATCH", query: [:], body: body, authorized: authorized)
    }

    /// DELETE → T
    func delete<T: Decodable>(_ path: String, query: [String: String] = [:], authorized: Bool = true) async throws -> T {
        try await request(path: path, method: "DELETE", query: query, body: Optional<EmptyEncodable>.none, authorized: authorized)
    }

    /// DELETE body → T (確認文字列が要るアカウント削除など)
    func delete<Body: Encodable, T: Decodable>(_ path: String, body: Body, authorized: Bool = true) async throws -> T {
        try await request(path: path, method: "DELETE", query: [:], body: body, authorized: authorized)
    }

    /// bodyless POST
    func postVoid<T: Decodable>(_ path: String, authorized: Bool = true) async throws -> T {
        try await request(path: path, method: "POST", query: [:], body: Optional<EmptyEncodable>.none, authorized: authorized)
    }

    // MARK: - Core

    private struct EmptyEncodable: Encodable {}

    private func request<Body: Encodable, T: Decodable>(
        path: String,
        method: String,
        query: [String: String],
        body: Body?,
        authorized: Bool
    ) async throws -> T {
        let url = try makeURL(path: path, query: query)
        var attempt = 0
        while true {
            var req = URLRequest(url: url)
            req.httpMethod = method
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")

            if authorized {
                guard let token = tokenProvider?.accessToken else {
                    throw APIError.notLoggedIn
                }
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            if let body = body, !(body is EmptyEncodable) {
                req.httpBody = try encoder.encode(body)
            }

            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: req)
            } catch let urlErr as URLError {
                // View が消えて Task がキャンセルされた場合など。ユーザーには見せない。
                if urlErr.code == .cancelled { throw APIError.cancelled }
                throw APIError.network(urlErr)
            }

            guard let http = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            if http.statusCode == 401, authorized, attempt == 0 {
                // 一度だけ refresh → retry
                do {
                    try await tokenProvider?.refreshTokens()
                } catch {
                    // refresh が「サーバの明示的な拒否 (4xx)」で失敗した場合だけ
                    // clearForLogout してセッション & DiskCache を破棄する。
                    // 通信断や 5xx など一時エラーで clear すると「電波の悪い場所で 1 API
                    // 叩いただけでキャッシュ全消し + ログイン画面」になり UX が悪い。
                    if (error as? APIError)?.isTerminalAuth == true {
                        await tokenProvider?.clearForLogout()
                        throw APIError.unauthorized
                    }
                    throw error
                }
                attempt += 1
                continue
            }

            if (200..<300).contains(http.statusCode) {
                if T.self == EmptyResponse.self {
                    return EmptyResponse() as! T
                }
                do {
                    let env = try decoder.decode(Envelope<T>.self, from: data)
                    if let data = env.data { return data }
                    // 稀に data フィールド無しで直接 T が返るケースにフォールバック
                    return try decoder.decode(T.self, from: data)
                } catch {
                    // T が envelope 外で直接返るタイプ (例: {"session":..}) 用フォールバック
                    if let bare = try? decoder.decode(T.self, from: data) { return bare }
                    throw APIError.decoding(error)
                }
            }

            // Error path
            if let env = try? decoder.decode(Envelope<T>.self, from: data), let e = env.error {
                throw APIError.server(status: http.statusCode, code: e.code, message: e.message)
            }
            if let bare = try? decoder.decode(EnvelopeErrorOnly.self, from: data) {
                throw APIError.server(status: http.statusCode, code: bare.error.code, message: bare.error.message)
            }
            throw APIError.server(status: http.statusCode, code: "http_\(http.statusCode)", message: "サーバエラー (HTTP \(http.statusCode))")
        }
    }

    private struct EnvelopeErrorOnly: Decodable {
        let error: APIErrorPayload
    }

    private func makeURL(path: String, query: [String: String]) throws -> URL {
        var comps = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false)!
        comps.path = path.hasPrefix("/") ? path : "/" + path
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw APIError.invalidResponse }
        return url
    }
}
