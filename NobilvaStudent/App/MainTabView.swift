import SwiftUI

/// メイン画面のタブ。生徒が日常的に使うのは「今日やること」と「先生とのやり取り」なので
/// 今日 / チャット / マイページの 3 つに絞る。計画一覧・学習記録・面談・設定は
/// マイページ (と今日画面のリンク) から辿る。
struct MainTabView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var chatUnread: ChatUnreadStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var timer: StudyTimer
    @EnvironmentObject var toast: ToastCenter

    enum Tab: Hashable {
        case today, chat, myPage
    }

    var body: some View {
        TabView(selection: $router.selectedTab) {
            TodayView()
                .tabItem { Label("今日", systemImage: "checklist") }
                .tag(Tab.today)

            ChatThreadListView()
                .tabItem { Label("チャット", systemImage: "bubble.left.and.bubble.right.fill") }
                .badge(chatUnread.totalUnread)
                .tag(Tab.chat)

            MyPageView()
                .tabItem { Label("マイページ", systemImage: "person.crop.circle.fill") }
                .tag(Tab.myPage)
        }
        .onChange(of: router.selectedTab) { _, new in
            if new == .chat { Task { await chatUnread.refresh() } }
        }
        .task {
            chatUnread.start(api: auth.api)
            timer.attach(api: auth.api)
        }
        .onDisappear { chatUnread.stop() }
        // タイマーで記録できたら、シートを閉じてトーストで知らせる (アラートで止めない)。
        .onChange(of: timer.lastRecord) { _, record in
            guard let record else { return }
            router.timerPresented = false
            // シートが閉じきってから出す (閉じるアニメーションの下に隠れないように)。
            Task {
                try? await Task.sleep(nanoseconds: 450_000_000)
                toast.show("\(record.label)の学習を記録しました")
            }
        }
        .sheet(isPresented: $router.timerPresented) {
            TimerView()
                .environmentObject(auth)
                .environmentObject(timer)
                .environmentObject(toast)
        }
        .sheet(item: $router.consulting) { req in
            TaskChatSheet(card: req.card, onSuccess: { toast.show("先生に相談を送りました") })
                .environmentObject(auth)
        }
    }
}
