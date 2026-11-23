import SwiftUI

/// 「マイページ」タブ。毎日は見ないが、ときどき確かめたいものをまとめる。
/// 上から「自分の学習」→「予定」→「設定」→「ヘルプ・アカウント」の順。
struct MyPageView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var tour: TourController
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var stats: StudyStats?
    @State private var planDays: [PlanDay] = PlanDay.from(PlanRepository.cachedPeriods() ?? [])
    /// iPhone: push した画面の積み重ね。
    @State private var path: [MyPageRoute] = []
    /// iPad: 右側に出している画面。最初は計画を出しておく (空の画面を見せない)。
    @State private var selection: MyPageRoute? = .plans(date: nil)
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showLogoutConfirm = false

    static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }()

    private var isRegular: Bool { sizeClass == .regular }

    var body: some View {
        Group {
            if isRegular {
                // iPad: 左にメニュー、右に選んだ画面 (設定アプリと同じ形)。
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    menu
                        .navigationSplitViewColumnWidth(min: 340, ideal: 380, max: 440)
                } detail: {
                    NavigationStack {
                        if let selection {
                            destination(selection)
                        } else {
                            ContentUnavailableView("項目を選んでください", systemImage: "person.crop.circle")
                        }
                    }
                    .id(selection)
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path: $path) {
                    menu
                        .navigationDestination(for: MyPageRoute.self) { destination($0) }
                }
            }
        }
        // push 先の画面でも計測バーを出すため、NavigationStack の外側に付ける。
        .timerAccessory()
    }

    /// 週の帯で日付を選んだら、その日の計画を開く。
    private func open(_ route: MyPageRoute) {
        if isRegular { selection = route } else { path.append(route) }
    }

    @ViewBuilder
    private var menu: some View {
        ScrollViewReader { proxy in
            Group {
                // iPad は選択中の行を強調するため selection 付きの List にする。
                if isRegular {
                    List(selection: $selection) { sections }
                } else {
                    List { sections }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("マイページ")
            // ツアーが画面外の行を指したらそこまでスクロールする。
            .onChange(of: tour.current?.target) { _, target in
                guard let target, tour.current?.tab == .myPage else { return }
                withAnimation { proxy.scrollTo(target, anchor: .center) }
            }
        }
        .task { await loadSummaries() }
        .onReceive(NotificationCenter.default.publisher(for: .studyDataDidChange)) { _ in
            Task { await loadSummaries() }
        }
    }

    @ViewBuilder
    private var sections: some View {
        Section {
            // 1 週間の計画をそのまま見せる。日付をタップするとその日の計画を開く。
            WeekStrip(days: PlanDay.week(from: planDays), selected: nil, fillsWidth: true) { open(.plans(date: $0)) }
                .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                .tourTarget(.myPageWeek)
                .id(TourTarget.myPageWeek)
            NavigationLink(value: MyPageRoute.plans(date: nil)) {
                LabeledRow("すべての計画", systemImage: "calendar")
            }
        } header: {
            Text("これからの計画")
        }

        Section {
            // 学習記録はここでそのまま見られるようにし、日ごとの内訳だけ詳細画面へ。
            Group {
                if let stats {
                    StudySummaryView(stats: stats)
                        .padding(.vertical, 8)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            .tourTarget(.myPageStats)
            .id(TourTarget.myPageStats)
        } header: {
            Text("学習記録")
        }

        Section("予定") {
            NavigationLink(value: MyPageRoute.meetings) {
                LabeledRow("面談", systemImage: "person.2.fill")
            }
            NavigationLink(value: MyPageRoute.busySlots) {
                LabeledRow("使えない時間", systemImage: "clock.badge.xmark")
            }
            .tourTarget(.myPageBusySlots)
            .id(TourTarget.myPageBusySlots)
        }

        Section("設定") {
            NavigationLink(value: MyPageRoute.account) {
                LabeledRow("アカウント", systemImage: "person.crop.circle")
            }
            NavigationLink(value: MyPageRoute.study) {
                LabeledRow("学年・学習時間", systemImage: "graduationcap")
            }
            NavigationLink(value: MyPageRoute.pomodoro) {
                LabeledRow("ポモドーロ", systemImage: "timer")
            }
            NavigationLink(value: MyPageRoute.notifications) {
                LabeledRow("通知", systemImage: "bell")
            }
            NavigationLink(value: MyPageRoute.security) {
                LabeledRow("パスキー・パスワード", systemImage: "lock.shield")
            }
        }

        Section("ヘルプ") {
            Button { tour.start() } label: {
                LabeledRow("使い方", systemImage: "questionmark.circle")
                    .foregroundStyle(Color.primary)
            }
            .tourTarget(.myPageGuide)
            .id(TourTarget.myPageGuide)
            ExternalLinkRow("利用規約", url: "https://nectere.jp/ja/legal/nobilva/terms-of-service")
            ExternalLinkRow("プライバシーポリシー", url: "https://nectere.jp/ja/legal/privacy-policy")
            ExternalLinkRow("特定商取引法に基づく表記", url: "https://nectere.jp/ja/legal/nobilva/commercial-disclosure")
        }

        Section {
            Button("ログアウト", role: .destructive) { showLogoutConfirm = true }
                .confirmationDialog("ログアウトしますか？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                    Button("ログアウト", role: .destructive) { Task { await auth.logout() } }
                }
            NavigationLink(value: MyPageRoute.deleteAccount) {
                Text("アカウントを削除").foregroundStyle(.red)
            }
        } footer: {
            Text("バージョン \(Self.appVersion)")
                .frame(maxWidth: .infinity)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func destination(_ route: MyPageRoute) -> some View {
        switch route {
        case .plans(let date): PlanListView(initialDate: date)
        case .meetings: MeetingListView()
        case .busySlots: BusySlotsEditorView()
        case .account: AccountView()
        case .study: StudySettingsView()
        case .pomodoro: PomodoroSettingsView()
        case .notifications: NotificationsSettingsView()
        case .security: SecuritySettingsView()
        case .deleteAccount: DeleteAccountView()
        }
    }
}

/// マイページから開ける画面。iPhone では push、iPad では右側に出す。
enum MyPageRoute: Hashable {
    case plans(date: String?)
    case meetings
    case busySlots
    case account
    case study
    case pomodoro
    case notifications
    case security
    case deleteAccount
}

extension MyPageView {
    fileprivate func loadSummaries() async {
        async let s = try? StudyStats.load(api: auth.api)
        async let p = try? PlanRepository(api: auth.api).fetchPeriods()
        if let value = await s { stats = value }
        if let periods = await p { planDays = PlanDay.from(periods) }
    }
}

/// アイコン + タイトル + 右寄せの値。リスト行の見た目をそろえる。
struct LabeledRow: View {
    let title: String
    let systemImage: String
    var value: String?

    init(_ title: String, systemImage: String, value: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.value = value
    }

    var body: some View {
        LabeledContent {
            if let value { Text(value).foregroundStyle(.secondary) }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}

/// 外部ページへのリンク行 (Safari で開くことが分かるよう矢印を付ける)。
struct ExternalLinkRow: View {
    let title: String
    let url: String

    init(_ title: String, url: String) {
        self.title = title
        self.url = url
    }

    var body: some View {
        if let u = URL(string: url) {
            Link(destination: u) {
                HStack {
                    Text(title).foregroundStyle(Color.primary)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}
