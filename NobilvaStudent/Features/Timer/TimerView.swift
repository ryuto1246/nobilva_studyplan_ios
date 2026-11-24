import SwiftUI
import UIKit

/// タイマーのシート。計測状態は StudyTimer (アプリ全体で 1 つ) が持つので、
/// シートを閉じても計測は続き、タブバー上の計測バーから戻ってこられる。
struct TimerView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var timer: StudyTimer
    @EnvironmentObject var toast: ToastCenter
    @Environment(\.dismiss) var dismiss

    /// 選べる「やること」は今日画面と同じもの (期限切れ・前日までの残り・今日の未完了)。
    @StateObject private var today = TodayViewModel()
    @State private var showManualSheet = false
    @State private var showDiscardConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    targetSection
                    if !timer.hasSession { modeSelector }
                    ring
                    if timer.snapshot.mode == .timer && !timer.hasSession { countdownStepper }
                    controls
                }
                .padding(20)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("タイマー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
                if !timer.hasSession {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("手動で記録") { showManualSheet = true }
                    }
                }
            }
            .task { await loadPrefs() }
            .task {
                today.inject(api: auth.api)
                await today.loadIfNeeded()
            }
            // 計測中にこの画面を開いている間だけ、画面を自動で消さない。
            .onAppear { UIApplication.shared.isIdleTimerDisabled = timer.isRunning }
            .onChange(of: timer.isRunning) { _, running in UIApplication.shared.isIdleTimerDisabled = running }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .errorAlert($timer.errorMessage)
            // シートの上でもトーストが見えるように (アプリのルートの表示はシートの下に隠れる)。
            .toastHost(toast)
            .sheet(isPresented: $showManualSheet) {
                // 記録 API は計画アイテムにしか紐付けられないので、タスクは選択肢に出さない。
                ManualRecordSheet(todayItems: today.actionable.filter { $0.kind == .planItem }, initialPlanItemId: timer.snapshot.item?.planItemId) { minutes in
                    toast.show("\(formatMinutes(minutes))の学習を記録しました")
                    dismiss()
                }
                .environmentObject(auth)
            }
        }
    }

    // MARK: - Sections

    /// 何に取り組むか。計測中は固定表示、計測前は今日のやることから選べる。
    @ViewBuilder
    private var targetSection: some View {
        if timer.hasSession {
            VStack(spacing: 4) {
                Text(timer.snapshot.item?.title ?? "自由学習")
                    .font(.title3.bold())
                    .multilineTextAlignment(.center)
                if let subject = timer.snapshot.item?.subject, !subject.isEmpty {
                    SubjectBadge(subject: subject)
                }
            }
        } else {
            Menu {
                Button("自由学習 (選ばない)") { timer.select(nil) }
                if !today.actionable.isEmpty {
                    Section("やること") {
                        ForEach(today.actionable) { item in
                            Button(item.title) { timer.select(item) }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("取り組むこと").font(.caption).foregroundStyle(.secondary)
                        Text(timer.snapshot.item?.title ?? "自由学習 (選ばない)")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
                .contentShape(Rectangle())
            }
            // Menu のラベルはアクセント色に塗られるので、通常の文字色に戻す。
            .tint(.primary)
            .accessibilityLabel("取り組むこと: \(timer.snapshot.item?.title ?? "自由学習")")
        }
    }

    private var modeSelector: some View {
        Picker("モード", selection: Binding(
            get: { timer.snapshot.mode },
            set: { timer.configure(mode: $0) }
        )) {
            ForEach(StudyTimer.Mode.allCases) { m in Text(m.label).tag(m) }
        }
        .pickerStyle(.segmented)
    }

    private var ring: some View {
        let r = timer.reading
        return TimerRing(
            progress: timer.progress,
            label: Self.clock(timer.displaySeconds),
            subLabel: ringCaption(r),
            tint: r.phase == .work || timer.snapshot.mode != .pomodoro ? Theme.accent : .green
        )
        .frame(width: 260, height: 260)
    }

    private func ringCaption(_ r: StudyTimer.Reading) -> String? {
        if r.finished { return "時間になりました" }
        switch timer.snapshot.mode {
        case .pomodoro:
            return r.phase == .work ? "作業 \(r.completedWorkPhases + 1)回目" : r.phase.label
        case .timer, .stopwatch:
            return timer.isPaused ? "一時停止中" : nil
        }
    }

    private var countdownStepper: some View {
        Stepper(value: Binding(
            get: { timer.snapshot.countdownMinutes },
            set: { timer.configure(countdownMinutes: $0) }
        ), in: 5...180, step: 5) {
            Text("時間: \(timer.snapshot.countdownMinutes)分")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
    }

    /// 計測前: 開始 / 計測中: 一時停止・記録 / 一時停止中: 再開・記録。
    @ViewBuilder
    private var controls: some View {
        if !timer.hasSession {
            PrimaryButton("開始", systemImage: "play.fill", isLoading: timer.isStarting) {
                Task { await timer.start() }
            }
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    if timer.isRunning {
                        SecondaryButton("一時停止", systemImage: "pause.fill") { timer.pause() }
                            .disabled(timer.isCompleting)
                    } else if !timer.reading.finished {
                        SecondaryButton("再開", systemImage: "play.fill") { timer.resume() }
                            .disabled(timer.isCompleting)
                    }
                    PrimaryButton("記録する", systemImage: "checkmark", isLoading: timer.isCompleting) {
                        Task { await timer.complete() }
                    }
                }
                Button("記録せずに終了", role: .destructive) { showDiscardConfirm = true }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .disabled(timer.isCompleting)
                    .confirmationDialog("記録せずに終了しますか？", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                        Button("記録せずに終了", role: .destructive) {
                            timer.discard()
                            toast.show("計測を終了しました", systemImage: "stop.circle.fill", tint: .secondary, feel: .warning)
                        }
                    } message: {
                        Text("ここまでの\(StudyTimer.RecordEvent(seconds: Int(timer.reading.studySeconds)).label)は記録されません。")
                    }

            }
        }
    }

    // MARK: - Helpers

    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    private func loadPrefs() async {
        guard let p = try? await TimerRepository(api: auth.api).pomodoroPrefs() else { return }
        timer.applyPomodoroPrefs(work: p.pomodoroWorkMinutes, shortBreak: p.pomodoroBreakMinutes,
                                 longBreak: p.pomodoroLongBreakMinutes)
    }

}

/// 手動記録シート。送信が成功してから閉じる。
private struct ManualRecordSheet: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) var dismiss
    let todayItems: [StudyItem]
    let onRecorded: (Int) -> Void

    @State private var minutes: Int = 30
    @State private var planItemId: String?
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(todayItems: [StudyItem], initialPlanItemId: String?, onRecorded: @escaping (Int) -> Void) {
        self.todayItems = todayItems
        self.onRecorded = onRecorded
        _planItemId = State(initialValue: initialPlanItemId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("\(formatMinutes(minutes))", value: $minutes, in: 5...600, step: 5)
                } header: {
                    Text("学習した時間")
                }
                if !todayItems.isEmpty {
                    Section("取り組んだこと (任意)") {
                        Picker("計画", selection: $planItemId) {
                            Text("選ばない").tag(String?.none)
                            ForEach(todayItems) { item in
                                Text(item.title).tag(String?.some(item.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("手動で記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button("記録") { Task { await save() } } }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($errorMessage)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await TimerRepository(api: auth.api).manual(planItemId: planItemId, durationMinutes: minutes)
            NotificationCenter.default.post(name: .studyDataDidChange, object: nil)
            dismiss()
            onRecorded(minutes)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "記録できませんでした"
        }
    }
}
