import SwiftUI
import UIKit

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
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var tour: TourController
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
                    // 計画にないことを勉強するときや、計画を終えたあとに自習するときの入口。
                    ToolbarItem(placement: .topBarLeading) {
                        Button { router.startTimer(for: nil, timer: timer) } label: {
                            Image(systemName: "timer")
                        }
                        .accessibilityLabel("タイマー")
                        .tourTarget(.todayTimerButton)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        // Label だとツールバーが UIKit の部品に置き換えて描画し、ツアーが
                        // 位置を取れないので Image + accessibilityLabel にしている。
                        Button { showAddTask = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("タスクを追加")
                        .tourTarget(.todayAddButton)
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
                    TaskFormView(existing: nil) { handleFormOutcome($0) }
                        .environmentObject(auth)
                }
                .sheet(item: $editingTask) { task in
                    TaskFormView(existing: task) { handleFormOutcome($0) }
                        .environmentObject(auth)
                }
                .errorAlert($vm.errorMessage)
                .onChange(of: vm.refreshFailedAt) { _, at in
                    if at != nil { toast.showError("最新の情報を読み込めませんでした") }
                }
        }
        // push 先の画面でも計測バーを出すため、NavigationStack の外側に付ける。
        .timerAccessory()
    }

    @ViewBuilder
    private var content: some View {
        switch vm.loadState {
        case .loading:
            LoadingStateView()
        case .failed:
            ScrollView { RetryStateView { await vm.load() }.padding(.top, 80) }
        case .loaded:
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        progressHeader
                        // 面談の当日は、やることより先に面談を見せる。
                        if vm.upcomingMeeting?.isToday == true { meetingSection }
                        focusSection
                            .tourTarget(focusItem != nil ? .todayFocus : nil)
                            .id(TourTarget.todayFocus)
                        nextUpSection
                            .tourTarget(nextUpItems.isEmpty ? nil : .todayNextUp)
                            .id(TourTarget.todayNextUp)
                        if vm.upcomingMeeting?.isToday != true { meetingSection }
                        unscheduledSection
                        completedSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                // ツアーが画面外の項目を指したらそこまでスクロールする。
                .onChange(of: tour.current?.target) { _, target in
                    guard let target, tour.current?.tab == .today else { return }
                    withAnimation { proxy.scrollTo(target, anchor: .center) }
                }
            }
        }
    }

    // MARK: - Sections

    /// 計画がまだ無い生徒のツアー中は、見本を出して場所を指せるようにする。
    private var focusItem: StudyItem? {
        vm.focus ?? (tour.isActive ? TourSample.focus : nil)
    }

    private var nextUpItems: [StudyItem] {
        vm.nextUp.isEmpty && tour.isActive ? TourSample.nextUp : vm.nextUp
    }

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

    /// 分母は今日の計画だけ。期限切れのタスクは別に数える (混ぜると数が合わなくなる)。
    private var progressText: String {
        var parts = [vm.todayDoneCount == vm.todayPlanCount
                     ? "今日の計画 \(vm.todayPlanCount)件 すべて完了"
                     : "今日の計画 \(vm.todayDoneCount)/\(vm.todayPlanCount)件 完了"]
        if vm.overdueOpenCount > 0 { parts.append("遅れているタスク \(vm.overdueOpenCount)件") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var focusSection: some View {
        if let focus = focusItem {
            FocusCard(
                item: focus,
                isTiming: timer.hasSession,
                onStart: { router.startTimer(for: focus, timer: timer) },
                onComplete: { toggle(focus) },
                onConsult: { router.consult(focus) }
            )
        } else if vm.todayPlanCount > 0 || !vm.completedToday.isEmpty {
            allDoneSection
        } else {
            VStack(spacing: 12) {
                InlineEmptyState(
                    title: "今日の計画はまだありません",
                    message: "何をやるか迷ったら、チャットで先生に相談しましょう。",
                    systemImage: "sun.max"
                )
                SecondaryButton("チャットを開く", systemImage: "bubble.left.and.bubble.right") {
                    router.selectedTab = .chat
                }
                freeStudyButton
            }
        }
    }

    /// 今日が全部終わったら、明日の予定を読み取り専用で見せる。
    @ViewBuilder
    private var allDoneSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 一日の区切りなので、ここだけはカードにして目立たせる。
            InlineEmptyState(
                title: "今日の計画はすべて完了しました",
                message: "お疲れさまでした。",
                systemImage: "checkmark.seal.fill"
            )
            .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            freeStudyButton
            if !vm.completedToday.isEmpty {
                SectionHeader("今日やったこと")
                StudyItemList(items: vm.completedToday, style: .plain) { item in
                    StudyItemRow(item: item, onToggle: { toggle(item) })
                }
            }
            if !vm.tomorrowPreview.isEmpty {
                SectionHeader("明日の予定") {
                    if let d = vm.tomorrowDate { Text(JSTDate.monthDay(d)).foregroundStyle(.secondary) }
                }
                StudyItemList(items: vm.tomorrowPreview, style: .plain, dividerInset: 12) { item in
                    StudyItemRow(item: item)
                }
            }
        }
    }

    /// やることが無いときに、計画に縛られずタイマーで勉強を始める。計測中は計測バーがあるので出さない。
    @ViewBuilder
    private var freeStudyButton: some View {
        if !timer.hasSession {
            SecondaryButton("タイマーで自習する", systemImage: "timer") {
                router.startTimer(for: nil, timer: timer)
            }
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private var nextUpSection: some View {
        if !nextUpItems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("次にやること")
                StudyItemList(items: nextUpItems, style: .plain) { item in
                    StudyItemRow(
                        item: item,
                        onToggle: { toggle(item) },
                        onTap: { router.startTimer(for: item, timer: timer) },
                        // 計測中は ▶ を出さない (押しても今の計測が開くだけなので)。
                        showsStartIcon: !timer.hasSession,
                        onConsult: { router.consult(item) },
                        onEdit: vm.task(id: item.id).map { t in { editingTask = t } }
                    )
                }
            }
        }
    }

    /// 今日完了したもの。やることの一覧とは分けて、折りたたんで置く。
    @ViewBuilder
    private var completedSection: some View {
        let done = vm.completedToday
        if !done.isEmpty && vm.focus != nil {
            VStack(alignment: .leading, spacing: 8) {
                CollapsibleHeader(title: "今日完了したもの (\(done.count)件)", isExpanded: $showCompleted)
                if showCompleted {
                    StudyItemList(items: done, style: .plain) { item in
                        StudyItemRow(item: item, onToggle: { toggle(item) })
                    }
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

    /// 完了 ⇄ 未完了を切り替え、結果をトーストで知らせる。完了は「元に戻す」で取り消せる。
    /// 押した瞬間に表示・トースト・振動を返す (通信は数秒かかることがあるため待たない)。
    /// 失敗したら表示を戻し、エラーを出す。
    private func toggle(_ item: StudyItem) {
        guard !TourSample.isSample(item) else { return }
        // タイマーを使わずに完了するときは、かかった時間を記録するよう促す。
        if vm.shouldAskRecordTime(item) {
            router.askRecordTime(for: item) { choice in
                switch choice {
                case .skip: completeWithoutRecord(item)
                case .record(let minutes):
                    toast.show("\(formatMinutes(minutes))を記録して完了しました")
                    Task { if await vm.recordAndComplete(item, minutes: minutes) == false { toast.dismiss() } }
                }
            }
            return
        }
        completeWithoutRecord(item)
    }

    private func completeWithoutRecord(_ item: StudyItem) {
        if item.isDone {
            toast.show("未完了に戻しました", systemImage: "arrow.uturn.backward.circle.fill", tint: .secondary, feel: .neutral)
        } else {
            toast.show("「\(item.title)」を完了しました", actionTitle: "元に戻す") {
                Task { await vm.toggle(item.withDone(true)) }
            }
        }
        Task {
            if await vm.toggle(item) == false { toast.dismiss() }
        }
    }

    private func handleFormOutcome(_ outcome: TaskFormView.Outcome) {
        switch outcome {
        case .added: toast.show("タスクを追加しました")
        case .updated: toast.show("タスクを保存しました")
        case .deleted(let id):
            vm.removeTask(id: id)
            toast.show("タスクを削除しました", systemImage: "trash.circle.fill", tint: .secondary, feel: .warning)
        }
        Task { await vm.load() }
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
                StudyItemList(items: open, style: .plain) { item in
                    StudyItemRow(
                        item: item,
                        onToggle: { toggle(item) },
                        onTap: { router.startTimer(for: item, timer: timer) },
                        showsStartIcon: !timer.hasSession,
                        onConsult: { router.consult(item) },
                        onEdit: { editingTask = vm.task(id: item.id) }
                    )
                }
            }
        }
    }
}
