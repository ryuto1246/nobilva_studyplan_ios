import Foundation
import SwiftUI

/// タブ横断の画面遷移 (タイマー / 相談シートを開く等) をまとめる軽量ルーター。
/// シートは MainTabView の 1 箇所だけで表示し、各画面は router を呼ぶだけにする。
@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: MainTabView.Tab = .today
    @Published var timerPresented: Bool = false
    @Published var consulting: ConsultRequest?
    /// 時間を記録せずに完了しようとしたときの確認。MainTabView がシートで出す。
    @Published var completing: CompletionRequest?

    struct CompletionRequest: Identifiable {
        let id = UUID()
        let item: StudyItem
        let onChoose: (RecordOnCompleteSheet.Choice) -> Void
    }

    init() {
        NotificationCenter.default.addObserver(forName: .userDidSignOut, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.timerPresented = false
                self?.consulting = nil
                self?.completing = nil
                self?.selectedTab = .today
            }
        }
    }

    struct ConsultRequest: Identifiable {
        let id = UUID()
        let card: ChatTaskCard
    }

    /// 「取り組む」。計測中なら対象は変えずにタイマーを開くだけ。
    func startTimer(for item: StudyItem?, timer: StudyTimer) {
        if !timer.hasSession { timer.select(item) }
        timerPresented = true
    }

    func askRecordTime(for item: StudyItem, onChoose: @escaping (RecordOnCompleteSheet.Choice) -> Void) {
        completing = CompletionRequest(item: item, onChoose: onChoose)
    }

    func consult(_ item: StudyItem) {
        consulting = ConsultRequest(card: item.consultCard)
    }
}
