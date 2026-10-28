import SwiftUI

/// メイン画面の Bottom Tab。各機能は Feature/* 配下の View。
struct MainTabView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var chatUnread: ChatUnreadStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var tour: TourController

    enum Tab: Hashable {
        case home, plan, chat, history, settings
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            DashboardView()
                .tabItem { Label("ホーム", systemImage: "house.fill") }
                .tag(Tab.home)

            NavigationStack { PlanListView() }
                .tabItem { Label("計画", systemImage: "calendar") }
                .tag(Tab.plan)

            ChatThreadListView()
                .tabItem { Label("チャット", systemImage: "bubble.left.and.bubble.right.fill") }
                .badge(chatUnread.totalUnread == 0 ? 0 : chatUnread.totalUnread)
                .tag(Tab.chat)
                .onChange(of: router.selectedTab) { _, new in
                    if new == .chat { Task { await chatUnread.refresh() } }
                }

            HistoryView()
                .tabItem { Label("履歴", systemImage: "chart.bar.fill") }
                .tag(Tab.history)

            SettingsIndexView()
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
                .tag(Tab.settings)
        }
        .toolbarBackground(.visible, for: .tabBar)
        .task { chatUnread.start(api: auth.api) }
        // 使い方ツアー。タブバーごと覆うので TabView の上に重ねる。
        .overlay { TourOverlay(tour: tour) }
        .onChange(of: tour.index) { _, _ in
            if let step = tour.current { router.selectedTab = step.tab }
            else { router.selectedTab = .home }
        }
        .task {
            // 初回ログイン後に一度だけ自動で開始。ホームの読み込みを少し待つ。
            guard !tour.hasCompleted else { return }
            try? await Task.sleep(nanoseconds: 800_000_000)
            if !tour.isActive { tour.start() }
        }
        // TodoRow の「取り組む」から呼ばれる: Timer を Sheet で表示。
        .sheet(isPresented: Binding(
            get: { router.timerPresented },
            set: { router.timerPresented = $0 }
        )) {
            NavigationStack { TimerView().environmentObject(auth).environmentObject(router) }
        }
    }
}
