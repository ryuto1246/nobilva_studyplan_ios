import SwiftUI

/// 「今日」タブ。生徒が開いた瞬間に「今なにをやればいいか」が分かることだけを目的にする。
///
/// 並び (上から重要な順):
///  1. 今日の進み具合 (1 行)
///  2. まずはこれ: 期限切れ → 今日の未完了のうち先頭 1 件を大きく
///  3. 次にやること: 残りを 1 本のリストで
///  4. 次の面談
///  5. 日付未定のタスク
///  6. 今日完了したもの (折りたたみ)
struct TodayView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var timer: StudyTimer
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm = TodayViewModel()

    @State private var showAddTask = false
    @State private var editingTask: StudentTask?
    @State private var showCompleted = false

    var body: some View {
        NavigationStack {
            content
                .background(Theme.groupedBackground.ignoresSafeArea())
                .navigationTitle("今日")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { showAddTask = true } label: {
                            Label("タスクを追加", systemImage: "plus")
                        }
                    }
                }
                .refreshable { await vm.load() }
                .task {
                    vm.inject(api: auth.api)
                    await vm.loadIfNeeded()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await vm.load() } }
                }
                .onReceive(NotificationCenter.default.publisher(for: .studyDataDidChange)) { _ in
                    Task { await vm.load() }
                }
                .sheet(isPresented: $showAddTask) {
                    TaskFormView(existing: nil) { Task { await vm.load() } }
                        .environmentObject(auth)
                }
                .sheet(item: $editingTask) { task in
                    TaskFormView(existing: task) { Task { await vm.load() } }
                        .environmentObject(auth)
                }
                .errorAlert($vm.errorMessage)
                .timerAccessory()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.loadState {
        case .loading:
            LoadingStateView()
        case .failed:
            ScrollView { RetryStateView { await vm.load() }.padding(.top, 80) }
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    progressHeader
                    // 面談の当日は、やることより先に面談を見せる。
                    if vm.upcomingMeeting?.isToday == true { meetingSection }
                    focusSection
                    nextUpSection
                    if vm.upcomingMeeting?.isToday != true { meetingSection }
                    unscheduledSection
                    completedSection
                    allPlansLink
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Sections

    /// 日付と「何件中何件」を 1 行で。大きな挨拶は置かず、情報だけを静かに見せる。
    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(JSTDate.displayMonthDay.string(from: Date()))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if vm.todayPlanCount > 0 {
                ProgressView(value: Double(vm.todayDoneCount), total: Double(vm.todayPlanCount))
                    .tint(Theme.accent)
                Text(progressText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var progressText: String {
        let remain = vm.actionable.count
        if remain == 0 { return "今日の計画 \(vm.todayPlanCount)件 すべて完了" }
        return "今日の計画 \(vm.todayDoneCount)/\(vm.todayPlanCount)件 完了 · 残り\(remain)件 約\(formatMinutes(vm.remainingMinutes))"
    }

    @ViewBuilder
    private var focusSection: some View {
        if let focus = vm.focus {
            FocusCard(
                item: focus,
                isTiming: timer.hasSession,
                onStart: { router.startTimer(for: focus, timer: timer) },
                onComplete: { Task { await vm.toggle(focus) } },
                onConsult: { router.consult(focus) }
            )
        } else if vm.todayPlanCount > 0 || !vm.completedToday.isEmpty {
            allDoneSection
        } else {
            InlineEmptyState(
                title: "今日の計画はまだありません",
                message: "何をやるか迷ったら、チャットで先生に相談しましょう。",
                systemImage: "sun.max"
            )
        }
    }

    /// 今日が全部終わったら、明日の予定を読み取り専用で見せる。
    @ViewBuilder
    private var allDoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            InlineEmptyState(
                title: "今日の計画はすべて完了しました",
                message: "お疲れさまでした。",
                systemImage: "checkmark.seal.fill"
            )
            if !vm.tomorrowPreview.isEmpty {
                SectionHeader("明日の予定") {
                    if let d = vm.tomorrowDate { Text(JSTDate.monthDay(d)).foregroundStyle(.secondary) }
                }
                StudyItemList(items: vm.tomorrowPreview) { item in
                    StudyItemRow(item: item)
                }
            }
        }
    }

    @ViewBuilder
    private var nextUpSection: some View {
        if !vm.nextUp.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("次にやること")
                StudyItemList(items: vm.nextUp) { item in
                    StudyItemRow(
                        item: item,
                        onToggle: { Task { await vm.toggle(item) } },
                        onTap: { router.startTimer(for: item, timer: timer) },
                        onConsult: { router.consult(item) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var meetingSection: some View {
        if let m = vm.upcomingMeeting {
            let isToday = m.isToday
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader(isToday ? "今日の面談" : "次の面談")
                VStack(alignment: .leading, spacing: 12) {
                    NavigationLink {
                        MeetingDetailView(meetingId: m.id)
                    } label: {
                        HStack {
                            MeetingSummary(meeting: m)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if let url = m.joinURL {
                        // 当日は主ボタン、それ以外は控えめに。
                        if isToday {
                            joinLink(url).buttonStyle(.borderedProminent)
                        } else {
                            joinLink(url).buttonStyle(.bordered)
                        }
                    }
                }
                .padding(16)
                .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
                .overlay {
                    if isToday {
                        RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
                    }
                }
            }
        }
    }

    private func joinLink(_ url: URL) -> some View {
        Link(destination: url) {
            Label("面談に参加", systemImage: "video.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 34)
        }
    }

    @ViewBuilder
    private var unscheduledSection: some View {
        let open = vm.unscheduled
        if !open.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("日付が決まっていないタスク")
                StudyItemList(items: open) { item in
                    StudyItemRow(
                        item: item,
                        onToggle: { Task { await vm.toggle(item) } },
                        onTap: { router.startTimer(for: item, timer: timer) },
                        onConsult: { router.consult(item) },
                        onEdit: { editingTask = vm.task(id: item.id) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private var completedSection: some View {
        let done = vm.completedToday
        if !done.isEmpty && vm.focus != nil {
            DisclosureGroup(isExpanded: $showCompleted) {
                StudyItemList(items: done) { item in
                    StudyItemRow(item: item, onToggle: { Task { await vm.toggle(item) } })
                }
                .padding(.top, 8)
            } label: {
                Text("今日完了したもの (\(done.count)件)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .tint(.secondary)
            .padding(.horizontal, 4)
        }
    }

    private var allPlansLink: some View {
        NavigationLink {
            PlanListView()
        } label: {
            HStack {
                Label("これからの計画をすべて見る", systemImage: "calendar")
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
            }
            .font(.body)
            .padding(16)
            .frame(minHeight: 44)
            .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
