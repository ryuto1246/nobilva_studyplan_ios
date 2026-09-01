import Foundation

/// タイマー本体。Date 差分で経過時間を計算し、Background 復帰後も正確に。
/// UI 更新用に 1 秒ごとの tick を発行するが、必要ないときは停止する。
@MainActor
final class PomodoroEngine: ObservableObject {
    enum Mode { case timer, pomodoro, stopwatch }
    enum Phase: String { case work = "作業", shortBreak = "休憩", longBreak = "長い休憩" }

    // 設定
    var workMinutes: Int = 25
    var breakMinutes: Int = 5
    var longBreakMinutes: Int = 15
    /// timer モードのカウントダウン初期値 (分)。
    var countdownMinutes: Int = 25

    // 実行状態
    @Published private(set) var mode: Mode = .pomodoro
    @Published private(set) var phase: Phase = .work
    @Published private(set) var isRunning = false
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var pomodoroCycle: Int = 0

    private var startedAt: Date?
    private var accumulatedBeforeStart: Int = 0
    private var timerTask: Task<Void, Never>?

    func setMode(_ m: Mode) {
        stop()
        mode = m
        elapsedSeconds = 0
        accumulatedBeforeStart = 0
        phase = .work
    }

    /// timer 用のカウントダウン値変更。
    func setCountdownMinutes(_ m: Int) {
        countdownMinutes = max(1, m)
    }

    // MARK: - Run/Pause

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startedAt = Date()
        scheduleEndNotification()
        startTick()
    }

    /// 現在のフェーズが満了するタイミングにローカル通知を仕込む。
    /// バックグラウンドで居ても end で通知が来て学習の中断を防げる。
    private func scheduleEndNotification() {
        guard mode == .pomodoro || mode == .timer else { return }
        let remaining = mode == .pomodoro
            ? totalSecondsForPhase() - currentElapsed
            : (countdownMinutes * 60) - currentElapsed
        guard remaining > 0 else { return }
        let title: String
        let body: String
        switch mode {
        case .pomodoro:
            title = "\(phase.rawValue) 終了"
            body = phase == .work ? "お疲れさま！休憩に入りましょう。" : "休憩終了。次の作業を始めましょう。"
        case .timer:
            title = "タイマー終了"
            body = "セッションを記録しましょう。"
        case .stopwatch:
            return
        }
        PushService.shared.scheduleLocal(
            after: TimeInterval(remaining),
            title: title, body: body,
            identifier: "pomodoro-phase-end"
        )
    }

    func pause() {
        guard isRunning, let started = startedAt else { return }
        accumulatedBeforeStart += Int(Date().timeIntervalSince(started))
        startedAt = nil
        isRunning = false
        stopTick()
        PushService.shared.cancelLocal(identifier: "pomodoro-phase-end")
    }

    func stop() {
        isRunning = false
        startedAt = nil
        elapsedSeconds = 0
        accumulatedBeforeStart = 0
        pomodoroCycle = 0
        phase = .work
        stopTick()
        PushService.shared.cancelLocal(identifier: "pomodoro-phase-end")
    }

    /// 呼び出した瞬間までの経過秒 (Date 差分で毎回計算)。
    var currentElapsed: Int {
        if let started = startedAt {
            return accumulatedBeforeStart + Int(Date().timeIntervalSince(started))
        }
        return accumulatedBeforeStart
    }

    /// UI 表示用の残り or 経過秒 (mode / phase 依存)。
    var displaySeconds: Int {
        switch mode {
        case .stopwatch:
            return currentElapsed
        case .timer:
            let total = countdownMinutes * 60
            return max(0, total - currentElapsed)
        case .pomodoro:
            let phaseTotal = totalSecondsForPhase()
            return max(0, phaseTotal - currentElapsed)
        }
    }

    /// 進捗 (0.0 - 1.0)。カウントダウン/pomodoro のみ意味を持つ。
    var progress: Double {
        switch mode {
        case .stopwatch: return 0
        case .timer:
            let total = Double(countdownMinutes * 60)
            return total > 0 ? min(1, Double(currentElapsed) / total) : 0
        case .pomodoro:
            let total = Double(totalSecondsForPhase())
            return total > 0 ? min(1, Double(currentElapsed) / total) : 0
        }
    }

    private func totalSecondsForPhase() -> Int {
        switch phase {
        case .work: return workMinutes * 60
        case .shortBreak: return breakMinutes * 60
        case .longBreak: return longBreakMinutes * 60
        }
    }

    /// 1 秒ごとの publisher。elapsedSeconds を更新して @Published を Kick する。
    private func startTick() {
        stopTick()
        timerTask = Task { [weak self] in
            while let self, await self.isRunning {
                await MainActor.run { self.elapsedSeconds = self.currentElapsed }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.checkPhaseTransition()
            }
        }
    }

    private func stopTick() {
        timerTask?.cancel()
        timerTask = nil
    }

    /// pomodoro 中に phase 満了なら次 phase へ。
    private func checkPhaseTransition() async {
        guard mode == .pomodoro, isRunning else { return }
        let total = totalSecondsForPhase()
        if currentElapsed >= total {
            // reset accumulator and switch phase
            accumulatedBeforeStart = 0
            startedAt = Date()
            switch phase {
            case .work:
                pomodoroCycle += 1
                phase = (pomodoroCycle % 4 == 0) ? .longBreak : .shortBreak
            case .shortBreak, .longBreak:
                phase = .work
            }
        }
    }
}
