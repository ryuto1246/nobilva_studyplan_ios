import SwiftUI

struct TimerView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var router: AppRouter
    @Environment(\.dismiss) var dismiss
    @StateObject private var engine = PomodoroEngine()

    @State private var mode: PomodoroEngine.Mode = .pomodoro
    @State private var todayItems: [PlanItem] = []
    @State private var selectedItemId: String? = nil
    @State private var sessionId: String? = nil
    @State private var errorMessage: String?
    @State private var showManualSheet = false
    @State private var recordedFlag = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    modeSelector
                    ringSection
                    countdownStepper
                    itemPicker
                    actionButtons
                    manualEntryButton
                }
                .padding(20)
            }
            .background(Theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("タイマー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
            .task { await loadPrefs(); await loadTodayItems(); adoptRouterPreselect() }
            .onChange(of: router.timerPreselectedPlanItemId) { _, _ in adoptRouterPreselect() }
            .alert("お疲れさま！", isPresented: $recordedFlag) {
                Button("OK") { recordedFlag = false }
            } message: {
                Text("学習を記録しました。")
            }
            .errorAlert($errorMessage)
            .sheet(isPresented: $showManualSheet) {
                ManualRecordSheet(todayItems: todayItems, initialPlanItemId: selectedItemId) { minutes, planItemId in
                    Task { await manualRecord(minutes: minutes, planItemId: planItemId) }
                }
                .environmentObject(auth)
            }
        }
    }

    private var modeSelector: some View {
        Picker("モード", selection: $mode) {
            Text("ポモドーロ").tag(PomodoroEngine.Mode.pomodoro)
            Text("タイマー").tag(PomodoroEngine.Mode.timer)
            Text("ストップウォッチ").tag(PomodoroEngine.Mode.stopwatch)
        }
        .pickerStyle(.segmented)
        .onChange(of: mode) { _, new in engine.setMode(new) }
    }

    private var ringSection: some View {
        TimerRing(
            progress: engine.progress,
            label: formatTime(engine.displaySeconds),
            subLabel: engine.mode == .pomodoro ? "\(engine.phase.rawValue) (\(engine.pomodoroCycle) 回目)" : nil,
            tint: engine.phase == .work ? Theme.accent : .green
        )
        .frame(width: 240, height: 240)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var countdownStepper: some View {
        if engine.mode == .timer && !engine.isRunning {
            Stepper("カウントダウン: \(engine.countdownMinutes) 分",
                    value: Binding(get: { engine.countdownMinutes }, set: { engine.setCountdownMinutes($0) }),
                    in: 5...180, step: 5)
        }
    }

    @ViewBuilder
    private var itemPicker: some View {
        if !todayItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("今日の計画から選択").font(.caption).foregroundStyle(.secondary)
                Picker("計画アイテム", selection: $selectedItemId) {
                    Text("(なし)").tag(String?.none)
                    ForEach(todayItems.sorted { $0.sortOrder < $1.sortOrder }) { item in
                        Text(item.title).tag(String?.some(item.id))
                    }
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.secondaryBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            if !engine.isRunning {
                Button {
                    Task { await startPressed() }
                } label: {
                    Label("開始", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    engine.pause()
                } label: {
                    Label("一時停止", systemImage: "pause.fill").frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await stopAndRecord() }
                } label: {
                    Label("完了", systemImage: "checkmark").frame(maxWidth: .infinity).padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
    }

    private var manualEntryButton: some View {
        Button {
            showManualSheet = true
        } label: {
            Label("手動で記録", systemImage: "square.and.pencil")
                .font(.subheadline)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.accent)
    }

    // MARK: - Helpers

    private func formatTime(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    // MARK: - Actions

    private func loadPrefs() async {
        do {
            let p = try await TimerRepository(api: auth.api).pomodoroPrefs()
            engine.workMinutes = p.pomodoroWorkMinutes
            engine.breakMinutes = p.pomodoroBreakMinutes
            engine.longBreakMinutes = p.pomodoroLongBreakMinutes
        } catch {
            // best-effort
        }
    }

    private func loadTodayItems() async {
        do {
            let today = try await TimerRepository(api: auth.api).todayPlan()
            todayItems = today.items
        } catch { /* silent */ }
    }

    private func startPressed() async {
        errorMessage = nil
        let sessionMode: SessionMode = {
            switch engine.mode {
            case .pomodoro: return .pomodoro
            case .timer: return .timer
            case .stopwatch: return .stopwatch
            }
        }()
        do {
            let resp = try await TimerRepository(api: auth.api).start(mode: sessionMode, planItemId: selectedItemId)
            sessionId = resp.sessionId
            engine.start()
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "セッションの開始に失敗しました"
        }
    }

    private func stopAndRecord() async {
        guard let sessionId else { engine.stop(); return }
        let elapsed = engine.currentElapsed
        engine.pause()
        do {
            _ = try await TimerRepository(api: auth.api).complete(sessionId: sessionId, durationSeconds: elapsed)
            recordedFlag = true
            self.sessionId = nil
            engine.stop()
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "記録に失敗しました"
        }
    }

    private func adoptRouterPreselect() {
        guard let id = router.timerPreselectedPlanItemId else { return }
        selectedItemId = id
        // 消化したので nil に戻す (次回 Timer タブに来た時に再適用されないように)
        router.timerPreselectedPlanItemId = nil
    }

    private func manualRecord(minutes: Int, planItemId: String?) async {
        do {
            _ = try await TimerRepository(api: auth.api).manual(planItemId: planItemId, durationMinutes: minutes)
            recordedFlag = true
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "記録に失敗しました"
        }
    }
}

/// 手動記録シート。
private struct ManualRecordSheet: View {
    @Environment(\.dismiss) var dismiss
    let todayItems: [PlanItem]
    let onSubmit: (Int, String?) -> Void

    @State private var minutes: Int = 30
    @State private var planItemId: String?

    init(todayItems: [PlanItem], initialPlanItemId: String?, onSubmit: @escaping (Int, String?) -> Void) {
        self.todayItems = todayItems
        self.onSubmit = onSubmit
        _planItemId = State(initialValue: initialPlanItemId)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper("時間: \(minutes) 分", value: $minutes, in: 5...600, step: 5)
                }
                if !todayItems.isEmpty {
                    Section("計画アイテムに紐付け (任意)") {
                        Picker("アイテム", selection: $planItemId) {
                            Text("(なし)").tag(String?.none)
                            ForEach(todayItems.sorted { $0.sortOrder < $1.sortOrder }) { item in
                                Text(item.title).tag(String?.some(item.id))
                            }
                        }
                    }
                }
                Section {
                    Button {
                        onSubmit(minutes, planItemId)
                        dismiss()
                    } label: {
                        Text("記録する").bold().frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("手動で記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
            }
        }
    }
}
