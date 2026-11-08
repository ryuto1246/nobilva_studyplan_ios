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
    @EnvironmentObject var tour: TourController
    @Environment(\.scenePhase) private var scenePhase
    /// 一度バックグラウンドに入ったか。復帰は background → inactive → active と
    /// 段階を踏むので、直前の値ではなくこのフラグで「戻ってきた」を判定する。
    @State private var wentToBackground = false

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
            // メイン画面が出た = ログイン済みでアプリを開いた。講師側で確認できるよう記録する。
            await AppOpenTracker.shared.record(api: auth.api)
        }
        // バックグラウンドから戻ってきたときも「開いた」として記録する。
        // (通知センターを下ろしただけの inactive → active は数えない)
        .onChange(of: scenePhase) { _, new in
            switch new {
            case .background:
                wentToBackground = true
            case .active where wentToBackground:
                wentToBackground = false
                guard auth.phase == .authenticated else { return }
                Task { await AppOpenTracker.shared.record(api: auth.api) }
            default:
                break
            }
        }
        .onDisappear { chatUnread.stop() }
        // 使い方ツアー。タブバーごと覆うので TabView の上に重ねる。
        .overlay { TourOverlay(tour: tour) }
        .onChange(of: tour.index) { _, _ in
            router.selectedTab = tour.current?.tab ?? .today
        }
        // 通知の許可はツアーが終わってから聞く (システムのダイアログで案内を遮らない)。
        .onChange(of: tour.isActive) { _, active in
            if !active, auth.phase == .authenticated { Task { await PushService.shared.requestAuthorizationAndRegister() } }
        }
        .task {
            tour.userId = auth.currentUser?.id
            guard !tour.hasCompleted else {
                await PushService.shared.requestAuthorizationAndRegister()
                return
            }
            // 初回ログイン後に一度だけ自動で開始。今日画面の読み込みを少し待つ。
            try? await Task.sleep(nanoseconds: 800_000_000)
            if !tour.isActive { tour.start() }
        }
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
        .sheet(item: $router.completing) { req in
            RecordOnCompleteSheet(item: req.item, onChoose: req.onChoose)
        }
        .sheet(item: $router.consulting) { req in
            TaskChatSheet(card: req.card, onSuccess: { toast.show("先生に相談を送りました") })
                .environmentObject(auth)
        }
    }
}
