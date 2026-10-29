import Foundation

/// 計画アイテム (PlanItem) とタスク (StudentTask) を、画面上は同じ「やること」として
/// 扱うための表示用モデル。行・フォーカスカード・タイマー・相談シートはすべてこれを受け取る。
struct StudyItem: Identifiable, Hashable {
    enum Kind: Hashable { case planItem, task }

    let id: String
    let kind: Kind
    let title: String
    let subject: String
    let minutes: Int
    let isDone: Bool
    /// 計画アイテムの plan_date。タスクでは nil。
    let date: String?
    let startTime: String?
    let dueDate: String?
    /// 締切 / 実施予定日のうち、遅れが大きい方の日数 (Web taskToActionable と同じ)。
    let overdueDays: Int
    let rationale: String?
    let sortOrder: Int
    /// 計画アイテムの元になったタスク。タスク自身では nil。
    let taskId: String?
    /// タスクに設定された「やりたい時間帯」。計画アイテムは startTime から決まるので nil。
    let preferredTimeOfDay: TimeOfDay?

    init(planItem p: PlanItem, date: String?) {
        id = p.id
        kind = .planItem
        title = p.title
        subject = p.subject
        minutes = p.durationMinutes
        isDone = p.status.isDone
        self.date = date
        startTime = p.startTime
        dueDate = nil
        // 前日までの計画は「N日遅れ」を出す (今日・先の日は 0)。
        overdueDays = date.map(JSTDate.daysOverdue) ?? 0
        // Web と同じく AI の「優先度」系の理由は出さない。
        rationale = (p.rationale?.contains("優先度") ?? true) ? nil : p.rationale
        sortOrder = p.sortOrder
        taskId = p.taskId
        preferredTimeOfDay = nil
    }

    init(task t: StudentTask) {
        id = t.id
        kind = .task
        title = t.title
        subject = t.subject
        minutes = t.estimatedMinutes
        isDone = t.status == .completed
        date = nil
        startTime = nil
        dueDate = t.dueDate
        overdueDays = [t.dueDate, t.scheduledDate].compactMap { $0 }.map(JSTDate.daysOverdue).max() ?? 0
        rationale = nil
        sortOrder = 0
        taskId = nil
        preferredTimeOfDay = t.preferredTimeOfDay
    }

    private init(copying o: StudyItem, isDone: Bool) {
        id = o.id; kind = o.kind; title = o.title; subject = o.subject; minutes = o.minutes
        self.isDone = isDone
        date = o.date; startTime = o.startTime; dueDate = o.dueDate; overdueDays = o.overdueDays
        rationale = o.rationale; sortOrder = o.sortOrder; taskId = o.taskId; preferredTimeOfDay = o.preferredTimeOfDay
    }

    /// 楽観的更新用。完了状態だけ差し替えたコピー。
    func withDone(_ done: Bool) -> StudyItem { StudyItem(copying: self, isDone: done) }

    /// セッション開始 API に渡す plan_item_id。タスクは紐付けない。
    var planItemId: String? { kind == .planItem ? id : nil }

    /// Web `startTimeToTimeOfDay` と同じ境界 (null は 9:00 扱い)。
    var timeOfDay: TimeOfDay {
        let value = String((startTime ?? "09:00").prefix(5))
        if value >= "17:00" { return .evening }
        if value >= "12:00" { return .afternoon }
        return .morning
    }

    /// 「（20問）」のような分量表記がタイトルにあればそれ、無ければ所要時間。
    var amountLabel: String {
        if let range = title.range(of: #"（([^）]+)）"#, options: .regularExpression) {
            return String(title[range].dropFirst().dropLast())
        }
        return formatMinutes(minutes)
    }

    /// 行に出す時間帯。計画アイテムは開始時刻から、タスクは設定されていればその時間帯。
    var timeOfDayLabel: String? {
        switch kind {
        case .planItem: return timeOfDay.label
        case .task: return preferredTimeOfDay?.label
        }
    }

    /// 行の 2 行目のうち科目以外 (時間帯・分量・期限)。科目は色付きバッジで別に出す。
    var detailText: String {
        var parts: [String] = [timeOfDayLabel, amountLabel].compactMap { $0 }
        if let dueDate, overdueDays == 0 { parts.append("期限 \(JSTDate.monthDay(dueDate))") }
        return parts.joined(separator: " · ")
    }

    var overdueLabel: String? { overdueDays > 0 ? "\(overdueDays)日遅れ" : nil }

    var consultCard: ChatTaskCard {
        switch kind {
        case .planItem: return .fromPlanItem(title: title, subject: subject, durationMinutes: minutes)
        case .task: return .fromTask(title: title, subject: subject, estimatedMinutes: minutes)
        }
    }

    /// 朝 → 昼 → 夜、同じ時間帯は sort_order の順 (Web slotOrder と同じ)。
    static func byTimeOfDay(_ a: StudyItem, _ b: StudyItem) -> Bool {
        let order: [TimeOfDay] = [.morning, .afternoon, .evening]
        let sa = order.firstIndex(of: a.timeOfDay) ?? 0
        let sb = order.firstIndex(of: b.timeOfDay) ?? 0
        return sa != sb ? sa < sb : a.sortOrder < b.sortOrder
    }
}
