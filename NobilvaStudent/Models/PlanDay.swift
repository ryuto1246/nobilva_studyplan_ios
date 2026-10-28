import Foundation

/// 1 日分の計画 (表示用)。計画一覧とマイページの週表示で共有する。
struct PlanDay: Identifiable, Hashable {
    let date: String
    let items: [StudyItem]

    var id: String { date }

    var doneCount: Int { items.filter(\.isDone).count }
    var totalMinutes: Int { items.reduce(0) { $0 + $1.minutes } }
    var isAllDone: Bool { !items.isEmpty && doneCount == items.count }

    /// 出てくる順に重複なしの科目。
    var subjects: [String] {
        var seen = Set<String>()
        return items.map(\.subject).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// "4件 · 約2時間" のような 1 行の要約。
    var summary: String {
        items.isEmpty ? "計画なし" : "\(items.count)件 · 約\(formatMinutes(totalMinutes))"
    }

    /// 計画期間のレスポンスを日付順の PlanDay にする。
    static func from(_ periods: [PeriodWithDays]) -> [PlanDay] {
        periods.flatMap(\.days)
            .compactMap { d -> PlanDay? in
                guard let date = d.plan?.planDate else { return nil }
                let items = d.items
                    .map { StudyItem(planItem: $0, date: date) }
                    .sorted(by: StudyItem.byTimeOfDay)
                return PlanDay(date: date, items: items)
            }
            .sorted { $0.date < $1.date }
    }

    /// 今日から n 日分。計画の無い日も「計画なし」として埋める。
    static func week(from days: [PlanDay], count: Int = 7) -> [PlanDay] {
        let byDate = Dictionary(days.map { ($0.date, $0) }, uniquingKeysWith: { a, _ in a })
        return (0..<count).map { offset in
            let date = JSTDate.todayString(offsetDays: offset)
            return byDate[date] ?? PlanDay(date: date, items: [])
        }
    }
}
