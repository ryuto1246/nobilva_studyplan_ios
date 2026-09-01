import Foundation
import SwiftUI

/// タブバーのチャットバッジ更新用の軽量ポーラー。
/// - 30 秒間隔で `/chat/unread/total` を叩く。
/// - Environment 化して MainTabView から参照。
@MainActor
final class ChatUnreadStore: ObservableObject {
    @Published private(set) var totalUnread: Int = 0
    private var pollTask: Task<Void, Never>?
    private weak var api: APIClient?

    func start(api: APIClient) {
        self.api = api
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// 手動リフレッシュ (チャットルームを閉じた直後などに呼ぶ)。
    func refresh() async {
        guard let api else { return }
        do {
            let n = try await ChatRepository(api: api).unreadTotal()
            totalUnread = n
        } catch {
            // silent — polling なのでエラーは無視
        }
    }
}
