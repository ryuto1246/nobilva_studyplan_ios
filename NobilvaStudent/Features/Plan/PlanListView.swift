import SwiftUI

/// これからの計画を日ごとに並べる補助画面 (今日画面・マイページから push)。
/// 毎日見るのは今日画面なので、ここは「先の予定を確かめる」用途に絞り、
/// 今日から先を上に、過去の分は折りたたんで下に置く。
struct PlanListView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var timer: StudyTimer
    @EnvironmentObject var toast: ToastCenter

    @State private var days: [PlanForDate] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var errorMessage: String?
    @State private var overrides: [String: Bool] = [:]
    @State private var showPast = false

    private let today = JSTDate.todayString()

    var body: some View {
        Group {
            if isLoading && days.isEmpty {
                LoadingStateView()
            } else if loadFailed && days.isEmpty {
                ScrollView { RetryStateView { await load() }.padding(.top, 80) }
            } else if days.isEmpty {
                ContentUnavailableView("計画はまだありません", systemImage: "calendar",
                                       description: Text("先生が計画を作ると、ここに日ごとに表示されます。"))
            } else {
                list
            }
        }
        .background(Theme.groupedBackground.ignoresSafeArea())
        .navigationTitle("計画")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if days.isEmpty, let cached = PlanRepository.cachedPeriods() { days = flatten(cached) }
            await load()
        }
        .refreshable { await load() }
        .errorAlert($errorMessage)
    }

    private var upcoming: [PlanForDate] { days.filter { ($0.plan?.planDate ?? "") >= today } }
    private var past: [PlanForDate] { days.filter { ($0.plan?.planDate ?? "") < today }.reversed() }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                if upcoming.isEmpty {
                    InlineEmptyState(title: "これからの計画はまだありません", systemImage: "calendar")
                }
                ForEach(upcoming, id: \.plan?.id) { day in daySection(day) }
                if !past.isEmpty {
                    CollapsibleHeader(title: "過去の計画 (\(past.count)日)", isExpanded: $showPast)
                    if showPast {
                        ForEach(past, id: \.plan?.id) { day in daySection(day) }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func daySection(_ day: PlanForDate) -> some View {
        let date = day.plan?.planDate ?? ""
        let items = day.items
            .map { apply(StudyItem(planItem: $0, date: date)) }
            .sorted(by: StudyItem.byTimeOfDay)
        let done = items.filter(\.isDone).count
        let isFuture = date > today
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(dayTitle(date)) {
                if !items.isEmpty {
                    Text(done == items.count ? "すべて完了" : "\(done)/\(items.count)件 完了")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            if items.isEmpty {
                InlineEmptyState(title: "この日の計画はありません", systemImage: "moon.zzz")
            } else {
                StudyItemList(items: items) { item in
                    StudyItemRow(
                        item: item,
                        onToggle: isFuture ? nil : { Task { await toggle(item) } },
                        // 先の日に「取り組む」は誤タップが痛いので出さない。
                        onTap: isFuture ? nil : { router.startTimer(for: item, timer: timer) },
                        onConsult: { router.consult(item) }
                    )
                }
            }
        }
    }

    private func dayTitle(_ date: String) -> String {
        let label = JSTDate.monthDay(date)
        if date == today { return "今日 \(label)" }
        if date == JSTDate.todayString(offsetDays: 1) { return "明日 \(label)" }
        return label
    }

    private func apply(_ item: StudyItem) -> StudyItem {
        guard let done = overrides[item.id], done != item.isDone else { return item }
        return item.withDone(done)
    }

    private func flatten(_ periods: [PeriodWithDays]) -> [PlanForDate] {
        periods.flatMap(\.days)
            .filter { $0.plan != nil }
            .sorted { ($0.plan?.planDate ?? "") < ($1.plan?.planDate ?? "") }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            days = flatten(try await PlanRepository(api: auth.api).fetchPeriods())
            overrides = [:]
            loadFailed = false
        } catch {
            loadFailed = true
            if !days.isEmpty, (error as? APIError)?.isCancelled != true {
                toast.showError("最新の計画を読み込めませんでした")
            }
        }
    }

    private func toggle(_ item: StudyItem) async {
        let next = !item.isDone
        let previous = overrides[item.id]
        overrides[item.id] = next
        // 押した瞬間に知らせる (通信を待たない)。
        if next {
            toast.show("「\(item.title)」を完了しました", actionTitle: "元に戻す") {
                Task { await toggle(item.withDone(true)) }
            }
        } else {
            toast.show("未完了に戻しました", systemImage: "arrow.uturn.backward.circle.fill", tint: .secondary, feel: .neutral)
        }
        do {
            try await TodayRepository(api: auth.api).setDone(item, done: next)
            NotificationCenter.default.post(name: .studyDataDidChange, object: nil)
        } catch {
            toast.dismiss()
            if overrides[item.id] == next { overrides[item.id] = previous }
            errorMessage = "更新できませんでした。通信状況を確認してください。"
        }
    }
}
