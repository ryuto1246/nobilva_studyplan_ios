import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var router: AppRouter
    @StateObject private var vm = DashboardViewModel()
    @State private var showBusyEditor = false
    /// エラー時にダイアログ表示する (画面内のカードでは出さない、統一方針)。
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            content
                .background(Theme.groupedBackground.ignoresSafeArea())
                .toolbar(.hidden, for: .navigationBar)
                .refreshable { await vm.refresh() }
                .task {
                    vm.inject(api: auth.api)
                    await vm.loadIfNeeded()
                }
                .onChange(of: vm.stateErrorMessage) { _, msg in errorMessage = msg }
                .errorAlert($errorMessage)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .idle, .loading:
            loadingView
        case .failed:
            // エラー内容はダイアログで出す。画面は再読み込みボタンだけの静かな空状態。
            emptyRetryView
        case .loaded(let summary):
            loadedView(summary)
        }
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
            Text("読み込み中…")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyRetryView: some View {
        VStack(spacing: 12) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Button("再読み込み") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func loadedView(_ s: DashboardSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroSection(s)
                if let m = s.upcomingMeeting { upcomingMeetingCard(m) }
                overdueSection(s)
                todayOrTomorrowSection(s)
                planEntryLink(s)
                busySlotsSection(s)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
    }

    /// Large Title 相当。iOS 標準アプリのタイトル位置に「こんにちは○○さん」を置く。
    /// 挨拶は時間帯で切り替え、その下に状況別のサブメッセージを大きめの 1 行で。
    private func heroSection(_ s: DashboardSummary) -> some View {
        let today = JSTDate.date(from: JSTDate.todayString()) ?? Date()
        let name = s.profile?.displayName ?? "あなた"
        return VStack(alignment: .leading, spacing: 4) {
            Text("\(greeting())、")
                .font(.system(size: 30, weight: .bold, design: .default))
                .foregroundStyle(.secondary)
            Text("\(name) さん")
                .font(.system(size: 36, weight: .heavy, design: .default))
                .foregroundStyle(Theme.accent)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(JSTDate.displayLong.string(from: today))
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
            Text(subMessage(s))
                .font(.title3.weight(.semibold))
                .foregroundStyle(subMessageTone(s))
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    /// 時間帯別挨拶。JST の時刻で分岐。
    private func greeting() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 4..<11: return "おはよう"
        case 11..<17: return "こんにちは"
        case 17..<22: return "こんばんは"
        default: return "おつかれさま"
        }
    }

    /// 状況に応じた一言。優先順位:
    ///  1) 期限切れタスクがあるなら promt
    ///  2) 今日の計画が全完了なら祝辞
    ///  3) 今日の残タスクを表示
    ///  4) 次の面談を軽く伝える
    ///  5) 日替わりの汎用エール
    private func subMessage(_ s: DashboardSummary) -> String {
        let todayItems = s.today?.plan?.items ?? []
        let doneToday = todayItems.filter { $0.status == .completed }.count
        let overdueCount = s.overdueTasks.count

        if overdueCount > 0 {
            return "期限切れのタスクが \(overdueCount) 件あるよ。"
        }
        if !todayItems.isEmpty && doneToday == todayItems.count {
            return "今日の計画は全部完了！おつかれさま。"
        }
        if !todayItems.isEmpty {
            let remain = todayItems.count - doneToday
            return "今日の計画はあと \(remain) 件。1つずつ片付けよう。"
        }
        if let m = s.upcomingMeeting, let start = JSTDate.parseTimestamp(m.scheduledStartAt) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "ja_JP")
            df.dateFormat = "M/d(E) HH:mm"
            df.timeZone = JSTDate.timeZone
            return "次の面談: \(df.string(from: start))"
        }
        let messages = [
            "今日は何を進めよう？",
            "少しずつが、いちばん確実。",
            "小さく続けるのが最強。"
        ]
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return messages[day % messages.count]
    }

    /// 期限切れ有り → orange、全完了 → green、それ以外 → secondary
    private func subMessageTone(_ s: DashboardSummary) -> Color {
        if s.overdueTasks.count > 0 { return .orange }
        let items = s.today?.plan?.items ?? []
        if !items.isEmpty && items.allSatisfy({ $0.status == .completed }) { return .green }
        return .secondary
    }

    private func upcomingMeetingCard(_ m: Meeting) -> some View {
        NavigationLink {
            MeetingDetailView(meetingId: m.id)
        } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "calendar.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("次の面談: \(m.title)").font(.headline)
                        if let start = JSTDate.parseTimestamp(m.scheduledStartAt) {
                            Text(JSTDate.displayLong.string(from: start) + " " + JSTDate.time.string(from: start))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func overdueSection(_ s: DashboardSummary) -> some View {
        if !s.overdueTasks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("期限切れのタスク", systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                Card {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(s.overdueTasks.enumerated()), id: \.element.id) { i, t in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(Theme.subjectColor(t.subject)).frame(width: 8, height: 8).padding(.top, 6)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t.title)
                                    if let due = t.dueDate {
                                        Text("期限: \(due)").font(.caption).foregroundStyle(.red)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, 6)
                            if i != s.overdueTasks.count - 1 { Divider() }
                        }
                    }
                }
            }
        }
    }

    /// 今日の計画があれば今日だけ、なければ明日を出す、両方無ければ空メッセージ。
    @ViewBuilder
    private func todayOrTomorrowSection(_ s: DashboardSummary) -> some View {
        let todayItems = s.today?.plan?.items ?? []
        let tomorrowItems = s.tomorrow?.plan?.items ?? []
        if !todayItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("今日の計画", systemImage: "sun.max.fill")
                planItemsCard(items: todayItems, emptyMessage: "")
            }
        } else if !tomorrowItems.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("明日の計画", systemImage: "moon.stars.fill")
                planItemsCard(items: tomorrowItems, emptyMessage: "")
            }
        } else {
            emptyPlanCard
        }
    }

    /// 「今日も明日も計画はありません」用の大きめ empty state。
    /// SF Symbol をブランド色で大きく置き、下に見出しと補足を並べる。
    /// (将来 unDraw の SVG に差し替える想定。SF Symbols は暫定表示)
    private var emptyPlanCard: some View {
        Card {
            VStack(spacing: 12) {
                Image(systemName: "moon.stars.circle.fill")
                    .font(.system(size: 72, weight: .regular))
                    .foregroundStyle(Theme.accent)
                    .padding(.top, 12)
                Text("計画はまだありません")
                    .font(.headline)
                Text("担当講師に相談して、\n今日やることを一緒に決めよう。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func planItemsCard(items: [PlanItem], emptyMessage: String) -> some View {
        Card {
            if items.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                let sorted = items.sorted { $0.sortOrder < $1.sortOrder }
                VStack(spacing: 0) {
                    ForEach(Array(sorted.enumerated()), id: \.element.id) { i, item in
                        TodoRow(
                            title: item.title,
                            subject: item.subject,
                            startTime: item.startTime,
                            durationMinutes: item.durationMinutes,
                            status: item.status,
                            prominent: i == 0 && item.status != .completed,
                            onToggle: { Task { await vm.toggleItem(item) } },
                            onStart: { router.startTimer(with: item.id) }
                        )
                        if i != sorted.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private func busySlotsSection(_ s: DashboardSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionTitle("使えない時間", systemImage: "clock.badge.exclamationmark.fill")
                Spacer()
                Button {
                    showBusyEditor = true
                } label: {
                    Label("編集", systemImage: "square.and.pencil")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Card {
                if s.busySlots.isEmpty {
                    Text("設定なし")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 6) {
                        ForEach(s.busySlots) { slot in
                            HStack(spacing: 10) {
                                Image(systemName: slot.source == .team ? "person.3.fill" : "person.fill")
                                    .foregroundStyle(Theme.secondaryLabel)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(slot.title).font(.subheadline)
                                    Text([slot.isWeekly ? "毎週\(slot.weekdayLabel)" : (slot.specificDate ?? ""), slot.timeOfDay.label]
                                        .filter { !$0.isEmpty }.joined(separator: " ・ "))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showBusyEditor) {
            BusySlotsEditorView()
                .environmentObject(auth)
        }
    }

    private func planEntryLink(_ s: DashboardSummary) -> some View {
        NavigationLink {
            MeetingListView()
                .environmentObject(auth)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                Text("面談一覧を見る").font(.body.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.secondaryBackground)
            .foregroundStyle(Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
