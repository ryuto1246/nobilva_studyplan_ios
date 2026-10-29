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
    /// 前日までの計画 (dashboard/summary には含まれないので計画一覧の API から取る)。
    @Published private(set) var pastPlanDays: [PlanDay] = []
    /// 今日すでに時間を記録した計画アイテム (完了時に記録を促さない)。
    private(set) var recordedToday: Set<String> = []
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

    /// 前日までにやり残した計画。直近の分だけ出す (計画の立て直しで残った古い項目が
    /// 溜まり続けないように)。期限切れタスクとして上に出ているものは重ねて出さない。
    /// 同じタスクの今日の分は別に数える (「3/20問」のように 1 つのタスクを日ごとに分けて
    /// 進めるため、昨日の分と今日の分は別のやること)。完了の判定はサーバーの状態で行い、
    /// 完了にした直後だけ「今日完了したもの」に残す (期限切れタスクと同じ)。
    private static let pastPlanLookbackDays = 7

    private var pastPlanItems: [StudyItem] {
        let from = JSTDate.todayString(offsetDays: -Self.pastPlanLookbackDays)
        let overdueTaskIds = Set((summary?.overdueTasks ?? []).map(\.id))
        return pastPlanDays
            .filter { $0.date >= from && $0.date < today }
            .flatMap(\.items)
            .filter { !$0.isDone }
            .filter { item in
                guard let taskId = item.taskId else { return true }
                return !overdueTaskIds.contains(taskId)
            }
            .map(apply)
    }

    private var todayItems: [StudyItem] {
        (summary?.today?.plan?.items ?? [])
            .map { apply(StudyItem(planItem: $0, date: summary?.today?.date)) }
            .sorted(by: StudyItem.byTimeOfDay)
    }

    /// 期限切れタスク → 前日までの計画の残り (古い日から) → 今日の未完了 (朝昼夜順)。
    var actionable: [StudyItem] {
        (overdueItems + pastPlanItems + todayItems).filter { !$0.isDone }
    }

    var focus: StudyItem? { actionable.first }
    var nextUp: [StudyItem] { Array(actionable.dropFirst()) }
    var completedToday: [StudyItem] { (overdueItems + pastPlanItems + todayItems).filter(\.isDone) }

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
    /// 期限切れとしてすでに上に出ているものは重ねて出さない。
    var unscheduled: [StudyItem] {
        let overdueIds = Set((summary?.overdueTasks ?? []).map(\.id))
        return unscheduledTasks
            .filter { !overdueIds.contains($0.id) }
            .map { apply(StudyItem(task: $0)) }
            .filter { !$0.isDone }
    }

    /// 編集できるタスク (日付未定・期限切れ)。計画アイテムは nil。
    func task(id: String) -> StudentTask? {
        unscheduledTasks.first { $0.id == id } ?? summary?.overdueTasks.first { $0.id == id }
    }

    var overdueOpenCount: Int { (overdueItems + pastPlanItems).filter { !$0.isDone }.count }

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
        if pastPlanDays.isEmpty, let cached = PlanRepository.cachedPeriods() {
            pastPlanDays = PlanDay.from(cached)
        }
        await load()
    }

    func load() async {
        guard let api else { return }
        async let summaryResult = Result(asyncCatching: { try await TodayRepository(api: api).fetchSummary() })
        async let tasksResult = Result(asyncCatching: { try await TasksRepository(api: api).listUnscheduled() })
        async let periodsResult = Result(asyncCatching: { try await PlanRepository(api: api).fetchPeriods() })

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
        // 前日までの残りは補足なので、取れなくても画面は出す。
        if case .success(let periods) = await periodsResult {
            pastPlanDays = PlanDay.from(periods)
        }
        if let ids = try? await SessionsRepository(api: api).recordedPlanItemIdsToday() {
            recordedToday = ids
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

    /// 完了にする前に、かかった時間を記録するよう促すべきか。
    func shouldAskRecordTime(_ item: StudyItem) -> Bool {
        !item.isDone && !recordedToday.contains(item.id)
    }

    /// 時間を記録して完了。失敗したら表示を戻す。
    @discardableResult
    func recordAndComplete(_ item: StudyItem, minutes: Int) async -> Bool {
        guard let api else { return false }
        let previous = overrides[item.id]
        overrides[item.id] = Override(done: true, at: Date())
        do {
            try await TodayRepository(api: api).recordAndComplete(item, minutes: minutes)
            recordedToday.insert(item.id)
            NotificationCenter.default.post(name: .studyDataDidChange, object: nil)
            return true
        } catch is TodayRepository.RecordedButNotCompleted {
            // 時間は記録済み。次に完了を押したときは記録を促さず、完了だけにする。
            recordedToday.insert(item.id)
            overrides[item.id] = previous
            NotificationCenter.default.post(name: .studyDataDidChange, object: nil)
            errorMessage = TodayRepository.recordedButNotCompletedMessage
            return false
        } catch {
            overrides[item.id] = previous
            errorMessage = "記録できませんでした。通信状況を確認してください。"
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
