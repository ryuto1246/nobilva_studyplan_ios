import Foundation

@MainActor
final class DashboardViewModel: ObservableObject {
    enum State {
        case idle
        case loading
        case loaded(DashboardSummary)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published var isRefreshing = false

    /// View 側で errorAlert 表示のトリガーに使う。
    var stateErrorMessage: String? {
        if case .failed(let msg) = state { return msg }
        return nil
    }

    /// AuthStore が持つ APIClient を View の task で inject する。
    /// (init で自前 APIClient を作ると tokenProvider が繋がらず 401 → "ログインが必要です"
    ///  になるので、必ず AuthStore.api を渡すこと。)
    private var repo: DashboardRepository?

    func inject(api: APIClient) {
        self.repo = DashboardRepository(api: api)
    }

    func loadIfNeeded() async {
        if case .loaded = state { return }
        // まずキャッシュがあれば即座に表示 (loading 状態をスキップ)
        if case .idle = state, let cached = DashboardRepository.cachedSummary() {
            state = .loaded(cached)
        }
        await load()
    }

    func load() async {
        guard let repo else { return }
        // すでにキャッシュから .loaded になっているなら loading に戻さない
        // (画面がチラつくのを防ぐ)
        if case .loaded = state { /* 維持 */ } else {
            state = .loading
        }
        do {
            let summary = try await repo.fetchSummary()
            state = .loaded(summary)
        } catch let e as APIError {
            // キャッシュ表示中なら失敗しても現状維持、cache も無い場合のみ .failed
            if case .loaded = state { return }
            state = .failed(e.errorDescription ?? "読み込みに失敗しました")
        } catch {
            if case .loaded = state { return }
            state = .failed("読み込みに失敗しました")
        }
    }

    func refresh() async {
        guard let repo else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let summary = try await repo.fetchSummary()
            state = .loaded(summary)
        } catch {
            // pull-to-refresh 時は既存表示を維持
        }
    }

    /// TodoRow から呼ばれる。
    func toggleItem(_ item: PlanItem) async {
        guard let repo else { return }
        let next: PlanItemStatus = item.status == .completed ? .pending : .completed
        // Optimistic update
        if case .loaded(var summary) = state {
            summary = mutate(summary) { s in
                if let idx = s.today?.plan?.items.firstIndex(where: { $0.id == item.id }) {
                    var copy = s.today?.plan?.items ?? []
                    copy[idx] = replacingStatus(copy[idx], with: next)
                    s = replacingTodayItems(s, items: copy)
                }
                if let idx = s.tomorrow?.plan?.items.firstIndex(where: { $0.id == item.id }) {
                    var copy = s.tomorrow?.plan?.items ?? []
                    copy[idx] = replacingStatus(copy[idx], with: next)
                    s = replacingTomorrowItems(s, items: copy)
                }
            }
            state = .loaded(summary)
        }
        do {
            try await repo.setPlanItemStatus(item.id, status: next)
        } catch {
            // 失敗時は再読み込みで整合を戻す
            await load()
        }
    }

    /// 期限切れタスクの完了トグル。完了になったら overdueTasks から消し、
    /// pending 復帰なら status 差し替えのみ。API は tasks/{id}/status。
    func toggleOverdueTask(_ task: StudentTask) async {
        guard let repo else { return }
        let next: TaskStatus = task.status == .completed ? .pending : .completed
        if case .loaded(var summary) = state {
            summary = mutate(summary) { s in
                if next == .completed {
                    s = replacingOverdue(s, tasks: s.overdueTasks.filter { $0.id != task.id })
                } else {
                    s = replacingOverdue(s, tasks: s.overdueTasks.map { t in
                        t.id == task.id ? replacingTaskStatus(t, with: next) : t
                    })
                }
            }
            state = .loaded(summary)
        }
        do {
            try await repo.setTaskStatus(task.id, status: next)
        } catch {
            await load()
        }
    }

    // MARK: - private helpers

    private func mutate<T>(_ v: T, _ f: (inout T) -> Void) -> T {
        var copy = v
        f(&copy)
        return copy
    }

    private func replacingStatus(_ item: PlanItem, with status: PlanItemStatus) -> PlanItem {
        PlanItem(
            id: item.id, planId: item.planId, taskId: item.taskId, goalId: item.goalId,
            title: item.title, subject: item.subject, startTime: item.startTime,
            durationMinutes: item.durationMinutes, status: status,
            rationale: item.rationale, sortOrder: item.sortOrder
        )
    }

    private func replacingTodayItems(_ s: DashboardSummary, items: [PlanItem]) -> DashboardSummary {
        DashboardSummary(
            profile: s.profile,
            today: DashboardDay(date: s.today?.date ?? "", plan: PlanForDate(plan: s.today?.plan?.plan, items: items)),
            tomorrow: s.tomorrow,
            overdueTasks: s.overdueTasks,
            chatPartners: s.chatPartners,
            busySlots: s.busySlots,
            upcomingMeeting: s.upcomingMeeting
        )
    }

    private func replacingTomorrowItems(_ s: DashboardSummary, items: [PlanItem]) -> DashboardSummary {
        DashboardSummary(
            profile: s.profile,
            today: s.today,
            tomorrow: DashboardDay(date: s.tomorrow?.date ?? "", plan: PlanForDate(plan: s.tomorrow?.plan?.plan, items: items)),
            overdueTasks: s.overdueTasks,
            chatPartners: s.chatPartners,
            busySlots: s.busySlots,
            upcomingMeeting: s.upcomingMeeting
        )
    }

    private func replacingOverdue(_ s: DashboardSummary, tasks: [StudentTask]) -> DashboardSummary {
        DashboardSummary(
            profile: s.profile,
            today: s.today,
            tomorrow: s.tomorrow,
            overdueTasks: tasks,
            chatPartners: s.chatPartners,
            busySlots: s.busySlots,
            upcomingMeeting: s.upcomingMeeting
        )
    }

    private func replacingTaskStatus(_ t: StudentTask, with status: TaskStatus) -> StudentTask {
        StudentTask(
            id: t.id, studentId: t.studentId, title: t.title, subject: t.subject,
            estimatedMinutes: t.estimatedMinutes, status: status,
            dueDate: t.dueDate, scheduledDate: t.scheduledDate,
            unitCount: t.unitCount, unitLabel: t.unitLabel,
            goalId: t.goalId, recurrence: t.recurrence,
            recurrenceWeekday: t.recurrenceWeekday,
            preferredTimeOfDay: t.preferredTimeOfDay, notes: t.notes,
            createdAt: t.createdAt
        )
    }
}
