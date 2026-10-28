import Foundation

/// 今日画面の状態。dashboard/summary と日付未定タスクを束ね、
/// 「まずはこれ → 次にやること → 完了」の並びを組み立てる。
@MainActor
final class TodayViewModel: ObservableObject {
    enum LoadState {
        case loading
        case loaded
        case failed
    }

    @Published private(set) var loadState: LoadState = .loading
    @Published private(set) var summary: DashboardSummary?
    @Published private(set) var unscheduledTasks: [StudentTask] = []
    @Published var errorMessage: String?
    /// 表示中のデータがある状態で再取得に失敗した時刻 (View がトーストで知らせる)。
    @Published private(set) var refreshFailedAt: Date?
    /// 楽観的に切り替えた完了状態。直後の再取得ではまだ古い状態が返ることがあるので、
    /// 再取得のたびに消さず、切り替えから一定時間は手元の状態を優先する。
    private struct Override { let done: Bool; let at: Date }
    @Published private var overrides: [String: Override] = [:]
    private static let overrideLifetime: TimeInterval = 30

    private var api: APIClient?

    func inject(api: APIClient) { self.api = api }

    // MARK: - Derived

    private var today: String { JSTDate.todayString() }

    private func apply(_ item: StudyItem) -> StudyItem {
        guard let done = overrides[item.id]?.done, done != item.isDone else { return item }
        return item.withDone(done)
    }

    private var overdueItems: [StudyItem] {
        (summary?.overdueTasks ?? []).map { apply(StudyItem(task: $0)) }
    }

    private var todayItems: [StudyItem] {
        (summary?.today?.plan?.items ?? [])
            .map { apply(StudyItem(planItem: $0, date: summary?.today?.date)) }
            .sorted(by: StudyItem.byTimeOfDay)
    }

    /// 期限切れ → 今日の未完了 (朝昼夜順)。Web の TodoNowSection と同じ優先順。
    var actionable: [StudyItem] {
        (overdueItems + todayItems).filter { !$0.isDone }
    }

    var focus: StudyItem? { actionable.first }
    var nextUp: [StudyItem] { Array(actionable.dropFirst()) }
    var completedToday: [StudyItem] { (overdueItems + todayItems).filter(\.isDone) }

    var todayPlanCount: Int { todayItems.count }
    var todayDoneCount: Int { todayItems.filter(\.isDone).count }
    var remainingMinutes: Int { actionable.reduce(0) { $0 + $1.minutes } }

    /// 今日の分がすべて終わったときだけ見せる明日の予定 (読み取り専用)。
    var tomorrowPreview: [StudyItem] {
        guard actionable.isEmpty else { return [] }
        return (summary?.tomorrow?.plan?.items ?? [])
            .map { StudyItem(planItem: $0, date: summary?.tomorrow?.date) }
            .sorted(by: StudyItem.byTimeOfDay)
    }

    var tomorrowDate: String? { summary?.tomorrow?.date }

    /// 日付未定のタスク (未完了のみ)。
    var unscheduled: [StudyItem] {
        unscheduledTasks.map { apply(StudyItem(task: $0)) }.filter { !$0.isDone }
    }

    /// 編集できるタスク (日付未定・期限切れ)。計画アイテムは nil。
    func task(id: String) -> StudentTask? {
        unscheduledTasks.first { $0.id == id } ?? summary?.overdueTasks.first { $0.id == id }
    }

    var overdueOpenCount: Int { overdueItems.filter { !$0.isDone }.count }

    var upcomingMeeting: Meeting? {
        guard let m = summary?.upcomingMeeting, m.isUpcoming else { return nil }
        return m
    }

    // MARK: - Loading

    func loadIfNeeded() async {
        // 前日のキャッシュは「今日」として見せない。
        if summary == nil, let cached = TodayRepository.cachedSummary(), cached.today?.date == today {
            summary = cached
            loadState = .loaded
        }
        if unscheduledTasks.isEmpty, let cached = TasksRepository.cachedUnscheduled() {
            unscheduledTasks = cached
        }
        await load()
    }

    func load() async {
        guard let api else { return }
        async let summaryResult = Result(asyncCatching: { try await TodayRepository(api: api).fetchSummary() })
        async let tasksResult = Result(asyncCatching: { try await TasksRepository(api: api).listUnscheduled() })

        switch await summaryResult {
        case .success(let s):
            summary = s
            overrides = overrides.filter { Date().timeIntervalSince($0.value.at) < Self.overrideLifetime }
            loadState = .loaded
        case .failure(let error):
            if summary == nil || summary?.today?.date != today {
                // 表示できるのが前日のデータだけなら、「今日」として見せない。
                summary = nil
                loadState = .failed
            } else if !(error is CancellationError), (error as? APIError)?.isCancelled != true {
                // 表示中のデータは残し、更新できなかったことだけ控えめに伝える。
                refreshFailedAt = Date()
            }
        }
        if case .success(let tasks) = await tasksResult {
            unscheduledTasks = tasks
        }
    }

    // MARK: - Mutations

    /// 完了トグル。失敗したら元に戻してエラーを出す。成功したら true。
    @discardableResult
    func toggle(_ item: StudyItem) async -> Bool {
        guard let api else { return false }
        let next = !item.isDone
        let previous = overrides[item.id]
        overrides[item.id] = Override(done: next, at: Date())
        do {
            try await TodayRepository(api: api).setDone(item, done: next)
            return true
        } catch {
            // 連打していても、この操作の前の状態に戻す。
            if overrides[item.id]?.done == next { overrides[item.id] = previous }
            errorMessage = "更新できませんでした。通信状況を確認してください。"
            return false
        }
    }

    /// 削除したタスクを、再取得を待たずに一覧から外す
    /// (削除直後の再取得では、まだ古い一覧が返ることがある)。
    func removeTask(id: String) {
        unscheduledTasks.removeAll { $0.id == id }
    }
}

private extension Result where Failure == Error {
    init(asyncCatching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
