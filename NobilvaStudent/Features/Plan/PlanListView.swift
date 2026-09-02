import SwiftUI

/// 学習計画タブ。Web と同じく "全期間の日を平坦に並べる" 形。
/// 生徒視点なので「今日何をやるか」がすぐ見え、上下スクロールで過去/未来が確認できる。
///
/// 構成:
///  1. 割り当てなしのタスク (scheduled_date が nil かつ plan_items 未参照のもの)
///  2. 学習計画: 日付昇順の Card 縦積み。今日は accent で強調。
struct PlanListView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var router: AppRouter

    /// buildDayEntries と同じ shape。過去→未来の順に並べ、今日が無い場合は
    /// placeholder を差し込んで「今日はまだ計画がありません」を出す。
    enum DayEntry: Hashable {
        case day(PlanForDate)
        case todayPlaceholder(date: String)

        var sortKey: String {
            switch self {
            case .day(let d): return d.plan?.planDate ?? ""
            case .todayPlaceholder(let date): return date
            }
        }
    }

    @State private var dayEntries: [DayEntry] = []
    @State private var unscheduledTasks: [StudentTask] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddTask = false
    @State private var editingTask: StudentTask?
    @State private var consulting: ConsultingRequest?

    /// `.sheet(item:)` 用の Identifiable wrapper。ChatTaskCard 自体は Hashable のみ。
    private struct ConsultingRequest: Identifiable {
        let id = UUID()
        let card: ChatTaskCard
    }

    private let today = JSTDate.todayString()

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if !unscheduledTasks.isEmpty {
                        unscheduledSection
                    }
                    daysSection
                }
                .padding(20)
            }
            .background(Theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("計画")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddTask = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .task {
                // キャッシュ即描画 (Plan periods + Tasks 両方)
                if dayEntries.isEmpty, let cached = PlanRepository.cachedPeriods() {
                    dayEntries = buildEntries(from: cached, today: today)
                }
                if unscheduledTasks.isEmpty, let cachedTasks = TasksRepository.cachedUnscheduled() {
                    unscheduledTasks = cachedTasks.filter { $0.status != .completed }
                }
                await load()
                try? await Task.sleep(nanoseconds: 200_000_000)
                withAnimation { proxy.scrollTo("today", anchor: .top) }
            }
            .refreshable { await load() }
            .sheet(isPresented: $showAddTask) {
                TaskFormView(existing: nil) { Task { await load() } }
                    .environmentObject(auth)
            }
            .sheet(item: $editingTask) { task in
                TaskFormView(existing: task) { Task { await load() } }
                    .environmentObject(auth)
            }
            .sheet(item: $consulting) { req in
                TaskChatSheet(card: req.card)
                    .environmentObject(auth)
            }
            .errorAlert($errorMessage)
        }
    }

    // MARK: - Unscheduled tasks

    private var unscheduledSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle("日付が決まっていないタスク", systemImage: "tray")
            Card {
                VStack(spacing: 0) {
                    ForEach(Array(unscheduledTasks.enumerated()), id: \.element.id) { i, task in
                        // 行全体タップで編集シート、Button (相談) は自分の onTap を優先。
                        // Button in Button だとインナー Button が反応しない iOS の仕様を避けるため
                        // 外側は onTapGesture、内側は Button を使う。
                        unscheduledRow(task)
                            .contentShape(Rectangle())
                            .onTapGesture { editingTask = task }
                        if i != unscheduledTasks.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private func unscheduledRow(_ task: StudentTask) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(Theme.subjectColor(task.subject)).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .foregroundStyle(Color.primary)
                HStack(spacing: 8) {
                    if !task.subject.isEmpty {
                        Text(task.subject).font(.caption).foregroundStyle(.secondary)
                    }
                    if let due = task.dueDate {
                        Text("期限 \(due)").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("\(task.estimatedMinutes)分").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button {
                consulting = ConsultingRequest(card: .fromTask(
                    title: task.title, subject: task.subject, estimatedMinutes: task.estimatedMinutes))
            } label: {
                Image(systemName: "message")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryLabel)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("このタスクについて相談する")
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Days

    @ViewBuilder
    private var daysSection: some View {
        if isLoading && dayEntries.isEmpty {
            HStack { Spacer(); ProgressView(); Spacer() }.padding(.top, 40)
        } else if errorMessage != nil {
            VStack(spacing: 12) {
                Image(systemName: "arrow.clockwise.circle")
                    .font(.largeTitle).foregroundStyle(.secondary)
                Button("再読み込み") { Task { await load() } }.buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity).padding(.top, 40)
        } else if dayEntries.isEmpty {
            Card {
                VStack(alignment: .leading, spacing: 6) {
                    Text("まだ計画がありません").font(.subheadline).bold()
                    Text("担当講師に計画を作ってもらいましょう。").font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            SectionTitle("学習計画", systemImage: "calendar")
            VStack(spacing: 12) {
                ForEach(dayEntries, id: \.self) { entry in
                    dayCard(entry)
                        .id(isToday(entry) ? "today" : entry.sortKey)
                }
            }
        }
    }

    private func isToday(_ entry: DayEntry) -> Bool {
        entry.sortKey == today
    }

    @ViewBuilder
    private func dayCard(_ entry: DayEntry) -> some View {
        switch entry {
        case .day(let plan):
            dayCardFilled(plan)
        case .todayPlaceholder(let date):
            dayCardEmpty(date: date, isToday: true)
        }
    }

    private func dayCardFilled(_ plan: PlanForDate) -> some View {
        let dateStr = plan.plan?.planDate ?? ""
        let isToday = dateStr == today
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                dayHeader(date: dateStr, isToday: isToday,
                          completed: plan.items.filter { $0.status == .completed }.count,
                          total: plan.items.count)
                if plan.items.isEmpty {
                    Text("この日の計画はありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    let sorted = plan.items.sorted { $0.sortOrder < $1.sortOrder }
                    ForEach(sorted) { item in
                        TodoRow(
                            title: item.title,
                            subject: item.subject,
                            startTime: item.startTime,
                            durationMinutes: item.durationMinutes,
                            status: item.status,
                            prominent: false,
                            onToggle: { Task { await toggleItem(item) } },
                            onStart: isToday ? { router.startTimer(with: item.id) } : nil,
                            onConsult: { consulting = ConsultingRequest(card: .fromPlanItem(
                                title: item.title, subject: item.subject, durationMinutes: item.durationMinutes)) }
                        )
                        if item.id != sorted.last?.id { Divider() }
                    }
                }
            }
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1.5)
            }
        }
    }

    private func dayCardEmpty(date: String, isToday: Bool) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                dayHeader(date: date, isToday: isToday, completed: 0, total: 0)
                Text(isToday ? "今日はまだ計画がありません" : "この日の計画はありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.5), lineWidth: 1.5)
            }
        }
    }

    private func dayHeader(date: String, isToday: Bool, completed: Int, total: Int) -> some View {
        let d = JSTDate.date(from: date) ?? Date()
        let label = JSTDate.displayShort.string(from: d)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.headline)
                .foregroundStyle(isToday ? Theme.accent : Color.primary)
            if isToday {
                Text("今日")
                    .font(.caption).bold()
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.15))
                    .foregroundStyle(Theme.accent)
                    .clipShape(Capsule())
            }
            Spacer()
            if total > 0 {
                Text("\(completed) / \(total)")
                    .font(.caption).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Load / actions

    private func load() async {
        isLoading = true; defer { isLoading = false }
        errorMessage = nil
        let repo = PlanRepository(api: auth.api)
        let taskRepo = TasksRepository(api: auth.api)
        do {
            async let periods = repo.fetchPeriods()
            async let tasks = taskRepo.listUnscheduled()
            let (fetchedPeriods, fetchedTasks) = try await (periods, tasks)
            dayEntries = buildEntries(from: fetchedPeriods, today: today)
            unscheduledTasks = fetchedTasks.filter { $0.status != .completed }
        } catch let e as APIError {
            if dayEntries.isEmpty && unscheduledTasks.isEmpty {
                errorMessage = e.errorDescription
            }
        } catch {
            if dayEntries.isEmpty && unscheduledTasks.isEmpty {
                errorMessage = "計画の読み込みに失敗しました"
            }
        }
    }

    /// Web の buildDayEntries と同じ挙動: 全 period の日を平坦化 & 日付昇順、
    /// 今日の実プランが無ければ間に placeholder を差し込む。
    private func buildEntries(from periods: [PeriodWithDays], today: String) -> [DayEntry] {
        let sortedDays = periods
            .flatMap { $0.days }
            .sorted { ($0.plan?.planDate ?? "") < ($1.plan?.planDate ?? "") }
        let hasToday = sortedDays.contains { $0.plan?.planDate == today }
        var entries: [DayEntry] = []
        var inserted = false
        for day in sortedDays {
            if !hasToday, !inserted, today < (day.plan?.planDate ?? "") {
                entries.append(.todayPlaceholder(date: today))
                inserted = true
            }
            entries.append(.day(day))
        }
        if !hasToday && !inserted {
            entries.append(.todayPlaceholder(date: today))
        }
        return entries
    }

    private func toggleItem(_ item: PlanItem) async {
        let next: PlanItemStatus = item.status == .completed ? .pending : .completed
        // Optimistic update: 先に表示を切り替え、失敗時に snapshot へ戻す
        let snapshot = dayEntries
        dayEntries = dayEntries.map { entry in
            guard case .day(let plan) = entry,
                  plan.items.contains(where: { $0.id == item.id }) else { return entry }
            let newItems = plan.items.map { i -> PlanItem in
                guard i.id == item.id else { return i }
                return PlanItem(
                    id: i.id, planId: i.planId, taskId: i.taskId, goalId: i.goalId,
                    title: i.title, subject: i.subject, startTime: i.startTime,
                    durationMinutes: i.durationMinutes, status: next,
                    rationale: i.rationale, sortOrder: i.sortOrder
                )
            }
            return .day(PlanForDate(plan: plan.plan, items: newItems))
        }
        do {
            try await PlanRepository(api: auth.api).setItemStatus(item.id, status: next)
        } catch {
            dayEntries = snapshot
            errorMessage = "更新に失敗しました"
        }
    }
}
