import Foundation

/// アプリ全体で共通のディスクキャッシュ。
///
/// - `Caches` ディレクトリ配下に `<key>.json` として Codable を書き出す。
/// - 起動直後の "空白時間" を消すため、Repository は取得成功時に write、
///   View は task 起動時にまず read で即描画 → 並行で fetch (SWR パターン)。
/// - ログアウト時に `clearAll()` で全消去。
enum DiskCache {
    private static let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let d = base.appendingPathComponent("nobilva-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    /// キャッシュ用の型付き key。中に enum で列挙して衝突を防ぐ。
    enum Key: String {
        case dashboardSummary = "dashboard-summary"
        case chatThreads = "chat-threads"
        case chatPartners = "chat-partners"
        case meetings = "meetings"
        case meetingsWithPast = "meetings-with-past"
        case tasks = "tasks"
        case periods = "plan-periods"
    }

    static func read<T: Decodable>(_ type: T.Type, key: Key) -> T? {
        let url = dir.appendingPathComponent(key.rawValue + ".json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func write<T: Encodable>(_ value: T, key: Key) {
        let url = dir.appendingPathComponent(key.rawValue + ".json")
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func clear(_ key: Key) {
        let url = dir.appendingPathComponent(key.rawValue + ".json")
        try? FileManager.default.removeItem(at: url)
    }

    /// ログアウト時に全消去。
    static func clearAll() {
        try? FileManager.default.removeItem(at: dir)
        _ = try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
}
