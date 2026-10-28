import Foundation
import SwiftUI

/// タブ横断の画面遷移 (タイマー / 相談シートを開く等) をまとめる軽量ルーター。
/// シートは MainTabView の 1 箇所だけで表示し、各画面は router を呼ぶだけにする。
@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: MainTabView.Tab = .today
    @Published var timerPresented: Bool = false
    @Published var consulting: ConsultRequest?

    struct ConsultRequest: Identifiable {
        let id = UUID()
        let card: ChatTaskCard
    }

    /// 「取り組む」。計測中なら対象は変えずにタイマーを開くだけ。
    func startTimer(for item: StudyItem?, timer: StudyTimer) {
        if !timer.hasSession { timer.select(item) }
        timerPresented = true
    }

    func consult(_ item: StudyItem) {
        consulting = ConsultRequest(card: item.consultCard)
    }
}
