import SwiftUI
import UIKit

/// 計画 (マイページ・今日画面から push)。
///
/// 構成:
///  1. 日付の帯: 計画のある全日程を横に並べ、選んだ日を下に出す (最初は今日)
///  2. 選んだ日の要約: 日付・件数・合計時間・完了数・科目
///  3. その日のやること
/// 縦に全日程を並べると目的の日にたどり着きにくいので、1 日ずつ見る形にしている。
struct PlanListView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var router: AppRouter
    @EnvironmentObject var timer: StudyTimer
    @EnvironmentObject var toast: ToastCenter

    /// 最初に開く日 (yyyy-MM-dd)。nil なら今日。
    var initialDate: String?

    @State private var days: [PlanDay] = []
    @State private var selected: String = JSTDate.todayString()
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var errorMessage: String?
    /// 楽観的に切り替えた完了状態。直後の再取得ではまだ古い状態が返ることがあるので、
    /// 切り替えから一定時間は手元の状態を優先する (今日画面と同じ)。
    private struct Override { let done: Bool; let at: Date }
    @State private var overrides: [String: Override] = [:]
    @State private var recordedToday: Set<String> = []

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
                content
            }
        }
        .background(Color(UIColor.systemBackground).ignoresSafeArea())
        .navigationTitle("計画")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if selected != today {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("今日") { selected = today }
                }
            }
        }
        .task {
            if let initialDate { selected = initialDate }
            if days.isEmpty, let cached = PlanRepository.cachedPeriods() { days = PlanDay.from(cached) }
            await load()
        }
        .refreshable { await load() }
        .errorAlert($errorMessage)
    }

    /// 帯に並べる日。計画のある日と今日 (計画が無くても) を合わせる。
    private var stripDays: [PlanDay] {
        var all = days
        if !all.contains(where: { $0.date == today }) { all.append(PlanDay(date: today, items: [])) }
        return all.sorted { $0.date < $1.date }.map(apply)
    }

    private var selectedDay: PlanDay {
        stripDays.first { $0.date == selected } ?? PlanDay(date: selected, items: [])
    }

    private var content: some View {
        VStack(spacing: 0) {
            WeekStrip(days: stripDays, selected: selected) { selected = $0 }
                .padding(.vertical, 8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    DaySummaryHeader(day: selectedDay, isToday: selected == today)
                        .padding(.bottom, 8)
                    dayItems(selectedDay)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
                .animation(.snappy, value: selected)
            }
        }
    }

    @ViewBuilder
    private func dayItems(_ day: PlanDay) -> some View {
        let isFuture = day.date > today
        if day.items.isEmpty {
            InlineEmptyState(title: "この日の計画はありません", systemImage: "moon.zzz")
        } else {
            let open = day.items.filter { !$0.isDone }
            let done = day.items.filter(\.isDone)
            if !open.isEmpty {
                StudyItemList(items: open, style: .plain, dividerInset: isFuture ? 12 : 56) { item in row(item, isFuture: isFuture) }
            }
            if !done.isEmpty {
                Text("完了したもの")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
                StudyItemList(items: done, style: .plain, dividerInset: isFuture ? 12 : 56) { item in row(item, isFuture: isFuture) }
            }
        }
    }

    private func row(_ item: StudyItem, isFuture: Bool) -> some View {
        StudyItemRow(
            item: item,
            onToggle: isFuture ? nil : { requestToggle(item) },
            // 先の日に「取り組む」は誤タップが痛いので出さない。
            onTap: isFuture || item.isDone ? nil : { router.startTimer(for: item, timer: timer) },
            showsStartIcon: !timer.hasSession,
            onConsult: { router.consult(item) }
        )
    }

    private func apply(_ day: PlanDay) -> PlanDay {
        PlanDay(date: day.date, items: day.items.map { item in
            guard let done = overrides[item.id]?.done, done != item.isDone else { return item }
            return item.withDone(done)
        })
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            days = PlanDay.from(try await PlanRepository(api: auth.api).fetchPeriods())
            overrides = overrides.filter { Date().timeIntervalSince($0.value.at) < 30 }
            loadFailed = false
            recordedToday = (try? await SessionsRepository(api: auth.api).recordedPlanItemIdsToday()) ?? recordedToday
        } catch {
            loadFailed = true
            if !days.isEmpty, (error as? APIError)?.isCancelled != true {
                toast.showError("最新の計画を読み込めませんでした")
            }
        }
    }

    /// 完了にするときは、時間を記録していなければ記録を促す。
    private func requestToggle(_ item: StudyItem) {
        guard !item.isDone, !recordedToday.contains(item.id) else {
            Task { await toggle(item) }
            return
        }
        router.askRecordTime(for: item) { choice in
            switch choice {
            case .skip: Task { await toggle(item) }
            case .record(let minutes): Task { await recordAndComplete(item, minutes: minutes) }
            }
        }
    }

    private func recordAndComplete(_ item: StudyItem, minutes: Int) async {
        let previous = overrides[item.id]
        overrides[item.id] = Override(done: true, at: Date())
        toast.show("\(formatMinutes(minutes))を記録して完了しました")
        do {
            try await TodayRepository(api: auth.api).recordAndComplete(item, minutes: minutes)
            recordedToday.insert(item.id)
            NotificationCenter.default.post(name: .studyDataDidChange, object: nil)
        } catch is TodayRepository.RecordedButNotCompleted {
            toast.dismiss()
            recordedToday.insert(item.id)
            overrides[item.id] = previous
            NotificationCenter.default.post(name: .studyDataDidChange, object: nil)
            errorMessage = TodayRepository.recordedButNotCompletedMessage
        } catch {
            toast.dismiss()
            overrides[item.id] = previous
            errorMessage = "記録できませんでした。通信状況を確認してください。"
        }
    }

    private func toggle(_ item: StudyItem) async {
        let next = !item.isDone
        let previous = overrides[item.id]
        overrides[item.id] = Override(done: next, at: Date())
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
            if overrides[item.id]?.done == next { overrides[item.id] = previous }
            errorMessage = "更新できませんでした。通信状況を確認してください。"
        }
    }
}

/// 選んだ日の要約: 日付 / 件数・時間・完了数 / 科目。
private struct DaySummaryHeader: View {
    let day: PlanDay
    let isToday: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text((isToday ? "今日 " : relativeLabel) + JSTDate.monthDay(day.date))
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if !day.items.isEmpty {
                    Text(day.isAllDone ? "すべて完了" : "\(day.doneCount)/\(day.items.count)件 完了")
                        .font(.subheadline)
                        .foregroundStyle(day.isAllDone ? .green : .secondary)
                        .monospacedDigit()
                }
            }
            if !day.items.isEmpty {
                ProgressView(value: Double(day.doneCount), total: Double(day.items.count))
                    .tint(Theme.accent)
                HStack(spacing: 6) {
                    Text(day.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(day.subjects, id: \.self) { SubjectBadge(subject: $0) }
                }
            }
        }
        .padding(.top, 4)
    }

    private var relativeLabel: String {
        day.date == JSTDate.todayString(offsetDays: 1) ? "明日 " : ""
    }
}
