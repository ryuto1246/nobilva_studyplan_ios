import SwiftUI

/// 「マイページ」タブ。毎日は見ないが、ときどき確かめたいものをまとめる。
/// 上から「自分の学習」→「予定」→「設定」→「ヘルプ・アカウント」の順。
struct MyPageView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var stats: StudyStats?
    @State private var showLogoutConfirm = false

    static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { HistoryView() } label: {
                        LabeledRow("学習記録", systemImage: "chart.bar.fill",
                                   value: stats.map { "直近7日 \(formatMinutes($0.totalMinutes))" })
                    }
                    NavigationLink { PlanListView() } label: {
                        LabeledRow("計画", systemImage: "calendar")
                    }
                } header: {
                    Text("学習")
                }

                Section("予定") {
                    NavigationLink { MeetingListView() } label: {
                        LabeledRow("面談", systemImage: "person.2.fill")
                    }
                    NavigationLink { BusySlotsEditorView() } label: {
                        LabeledRow("使えない時間", systemImage: "clock.badge.xmark")
                    }
                }

                Section("設定") {
                    NavigationLink { AccountView() } label: {
                        LabeledRow("アカウント", systemImage: "person.crop.circle")
                    }
                    NavigationLink { StudySettingsView() } label: {
                        LabeledRow("学年・学習時間", systemImage: "graduationcap")
                    }
                    NavigationLink { PomodoroSettingsView() } label: {
                        LabeledRow("ポモドーロ", systemImage: "timer")
                    }
                    NavigationLink { NotificationsSettingsView() } label: {
                        LabeledRow("通知", systemImage: "bell")
                    }
                    NavigationLink { SecuritySettingsView() } label: {
                        LabeledRow("パスキー・パスワード", systemImage: "lock.shield")
                    }
                }

                Section("ヘルプ") {
                    NavigationLink { GuideView() } label: {
                        LabeledRow("使い方", systemImage: "questionmark.circle")
                    }
                    ExternalLinkRow("利用規約", url: "https://nectere.jp/ja/legal/nobilva/terms-of-service")
                    ExternalLinkRow("プライバシーポリシー", url: "https://nectere.jp/ja/legal/privacy-policy")
                    ExternalLinkRow("特定商取引法に基づく表記", url: "https://nectere.jp/ja/legal/nobilva/commercial-disclosure")
                }

                Section {
                    Button("ログアウト", role: .destructive) { showLogoutConfirm = true }
                        .confirmationDialog("ログアウトしますか？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                            Button("ログアウト", role: .destructive) { Task { await auth.logout() } }
                        }
                    NavigationLink { DeleteAccountView() } label: {
                        Text("アカウントを削除").foregroundStyle(.red)
                    }
                } footer: {
                    Text("バージョン \(Self.appVersion)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("マイページ")
            .task { stats = try? await StudyStats.load(api: auth.api) }
            .onReceive(NotificationCenter.default.publisher(for: .studyDataDidChange)) { _ in
                Task { stats = try? await StudyStats.load(api: auth.api) }
            }
        }
        // push 先の画面でも計測バーを出すため、NavigationStack の外側に付ける。
        .timerAccessory()
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
