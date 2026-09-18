import Foundation
import SwiftUI

/// タブ横断のちょっとした指示 (「タイマータブに切り替えてこの PlanItem を選ぶ」等) を
/// 運ぶための軽量ルーター。View 側は @EnvironmentObject で購読。
@MainActor
final class AppRouter: ObservableObject {
    @Published var selectedTab: MainTabView.Tab = .home
    /// Timer 画面が起動時に読み取る「これで走らせろ」指示。
    @Published var timerPreselectedPlanItemId: String?
    /// Timer 画面を Sheet で開くフラグ (タブ廃止に伴い、Dashboard/Plan の "取り組む" から呼ぶ)。
    @Published var timerPresented: Bool = false

    func startTimer(with planItemId: String) {
        timerPreselectedPlanItemId = planItemId
        timerPresented = true
    }

    /// PlanItem に紐付かない「取り組む」用。未日付タスクからのショートカット。
    /// Timer sheet が開いた後、ユーザが必要なら手動で今日の item を選択する。
    func openTimer() {
        timerPreselectedPlanItemId = nil
        timerPresented = true
    }
}
