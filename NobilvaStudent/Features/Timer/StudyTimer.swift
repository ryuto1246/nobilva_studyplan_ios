import Foundation
import UIKit

/// アプリ全体で 1 つだけ持つ学習タイマー。
///
/// - 状態は「基準点 (一時停止時点の値) + 再開時刻」だけを保持し、表示値は毎回
///   `now` から計算する。tick は再描画のきっかけでしかないので、バックグラウンドや
///   アプリ終了をまたいでも UserDefaults の snapshot から正確に復元できる。
/// - ポモドーロは経過時間を各フェーズに順に割り当てて現在フェーズを求める。
///   記録する学習時間は作業フェーズの合計だけ。
/// - サーバのセッションは開始時に作るが、失敗しても計測は止めない。
///   完了時に sessionId が無ければ作り直してから complete する。
@MainActor
final class StudyTimer: ObservableObject {
    enum Mode: String, Codable, CaseIterable, Identifiable {
        case pomodoro, timer, stopwatch
        var id: String { rawValue }
        var label: String {
            switch self {
            case .pomodoro: return "ポモドーロ"
            case .timer: return "タイマー"
            case .stopwatch: return "ストップウォッチ"
            }
        }
        var sessionMode: SessionMode {
            switch self {
            case .pomodoro: return .pomodoro
            case .timer: return .timer
            case .stopwatch: return .stopwatch
            }
        }
    }

    enum Phase: String, Codable {
        case work, shortBreak, longBreak
        var label: String {
            switch self {
            case .work: return "作業"
            case .shortBreak: return "休憩"
            case .longBreak: return "長い休憩"
            }
        }
    }

    /// 永続化する唯一の状態。
    struct Snapshot: Codable, Equatable {
        var mode: Mode = .pomodoro
        var workMinutes = 25
        var breakMinutes = 5
        var longBreakMinutes = 15
        var countdownMinutes = 25
        // 基準点
        var phase: Phase = .work
        var phaseElapsed: Double = 0
        var studySeconds: Double = 0
        var completedWorkPhases = 0
        /// 走行中のみ非 nil。
        var resumedAt: Date?
        // 紐付け
        var item: StudyItemRef?
        var sessionId: String?
        var startedAt: Date?
    }

    /// 計測対象。StudyItem 全体は持たず、表示と API に必要な分だけ。
    struct StudyItemRef: Codable, Equatable {
        let planItemId: String?
        let title: String
        let subject: String
    }

    /// `now` 時点の計算結果。
    struct Reading {
        let phase: Phase
        let phaseElapsed: Double
        let studySeconds: Double
        let completedWorkPhases: Int
        let finished: Bool
    }

    @Published private(set) var snapshot: Snapshot { didSet { persist() } }
    /// 1 秒ごとに更新して再描画させる。
    @Published private(set) var now = Date()
    @Published private(set) var isStarting = false
    @Published private(set) var isCompleting = false
    @Published var errorMessage: String?
    /// 記録に成功した分数。View がアラート表示に使い、閉じたら nil に戻す。
    @Published var recordedMinutes: Int?

    private var api: APIClient?
    private var tickTask: Task<Void, Never>?
    private static let storageKey = "study-timer.snapshot.v1"
    private static let notificationIds = (0..<8).map { "study-timer-phase-\($0)" }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            snapshot = saved
        } else {
            snapshot = Snapshot()
        }
        if snapshot.resumedAt != nil { startTick() }
        signOutObserver = NotificationCenter.default.addObserver(
            forName: .userDidSignOut, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.discard() }
        }
    }

    private var signOutObserver: NSObjectProtocol?

    func attach(api: APIClient) { self.api = api }

    // MARK: - Derived state

    /// 計測を始めてから完了 / 破棄するまで true (一時停止中も含む)。
    var hasSession: Bool { snapshot.startedAt != nil }
    var isRunning: Bool { snapshot.resumedAt != nil && !reading.finished }
    var isPaused: Bool { hasSession && !isRunning }

    var reading: Reading { Self.project(snapshot, at: now) }

    /// リングの中央に出す秒数。ポモドーロとタイマーは残り、ストップウォッチは経過。
    var displaySeconds: Int {
        let r = reading
        switch snapshot.mode {
        case .pomodoro: return max(0, Int((phaseLength(r.phase, snapshot) - r.phaseElapsed).rounded(.up)))
        case .timer: return max(0, Int((Double(snapshot.countdownMinutes * 60) - r.studySeconds).rounded(.up)))
        case .stopwatch: return Int(r.studySeconds)
        }
    }

    var progress: Double {
        let r = reading
        switch snapshot.mode {
        case .pomodoro: return min(1, r.phaseElapsed / max(1, phaseLength(r.phase, snapshot)))
        case .timer: return min(1, r.studySeconds / Double(max(1, snapshot.countdownMinutes * 60)))
        case .stopwatch: return 0
        }
    }

    var studyMinutes: Int { Int(reading.studySeconds / 60) }

    // MARK: - Configuration (計測前のみ)

    func configure(mode: Mode? = nil, countdownMinutes: Int? = nil) {
        guard !hasSession else { return }
        var s = snapshot
        if let mode { s.mode = mode }
        if let countdownMinutes { s.countdownMinutes = max(1, countdownMinutes) }
        snapshot = s
    }

    func applyPomodoroPrefs(work: Int, shortBreak: Int, longBreak: Int) {
        guard !hasSession else { return }
        var s = snapshot
        s.workMinutes = work; s.breakMinutes = shortBreak; s.longBreakMinutes = longBreak
        snapshot = s
    }

    func select(_ item: StudyItem?) {
        guard !hasSession else { return }
        snapshot.item = item.map { StudyItemRef(planItemId: $0.planItemId, title: $0.title, subject: $0.subject) }
    }

    // MARK: - Actions

    func start() async {
        guard !hasSession, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        let startedAt = Date()
        var s = snapshot
        s.phase = .work; s.phaseElapsed = 0; s.studySeconds = 0; s.completedWorkPhases = 0
        s.startedAt = startedAt; s.resumedAt = startedAt; s.sessionId = nil
        snapshot = s
        now = startedAt
        startTick()
        scheduleNotifications()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let sessionId = try? await createServerSession()
        // 応答待ちの間に破棄・完了されていたら、別の計測に紐付けない。
        if snapshot.startedAt == startedAt, snapshot.sessionId == nil {
            snapshot.sessionId = sessionId
        }
    }

    func pause() {
        guard isRunning else { return }
        freezeBaseline()
        stopTick()
        cancelNotifications()
    }

    func resume() {
        guard isPaused, !reading.finished else { return }
        snapshot.resumedAt = Date()
        now = Date()
        startTick()
        scheduleNotifications()
    }

    /// 記録して終了。失敗したら一時停止状態のまま残し、もう一度押せば再送できる。
    func complete() async {
        guard hasSession, !isCompleting else { return }
        isCompleting = true
        defer { isCompleting = false }
        freezeBaseline()
        stopTick()
        cancelNotifications()
        let seconds = Int(snapshot.studySeconds)
        do {
            let sessionId: String
            if let existing = snapshot.sessionId {
                sessionId = existing
            } else {
                sessionId = try await createServerSession()
                snapshot.sessionId = sessionId
            }
            guard let api else { throw APIError.notLoggedIn }
            let _: SessionCompletedResponse = try await TimerRepository(api: api)
                .complete(sessionId: sessionId, durationSeconds: seconds)
            recordedMinutes = max(1, seconds / 60)
            reset()
            NotificationCenter.default.post(name: .studyDataDidChange, object: nil)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription
                ?? "記録できませんでした。通信状況を確認して、もう一度「記録する」を押してください。"
        }
    }

    /// 記録せずに破棄する。開始済みのサーバセッションは取消 API で消す (best-effort)。
    func discard() {
        let sessionId = snapshot.sessionId
        stopTick()
        cancelNotifications()
        reset()
        if let sessionId, let api {
            Task { try? await TimerRepository(api: api).cancel(sessionId: sessionId) }
        }
    }

    // MARK: - Projection

    /// snapshot の基準点に (now - resumedAt) を足した状態を返す純関数。
    static func project(_ s: Snapshot, at now: Date) -> Reading {
        var phase = s.phase
        var phaseElapsed = s.phaseElapsed
        var study = s.studySeconds
        var cycles = s.completedWorkPhases
        var finished = false
        var delta = s.resumedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0

        switch s.mode {
        case .stopwatch:
            study += delta
        case .timer:
            let total = Double(s.countdownMinutes * 60)
            study = min(total, study + delta)
            finished = study >= total
        case .pomodoro:
            // 数日放置されても止まるよう、割り当て回数に上限を置く。
            var guardCount = 0
            while delta > 0 && guardCount < 1000 {
                guardCount += 1
                let remaining = phaseLengthStatic(phase, s) - phaseElapsed
                if delta < remaining {
                    phaseElapsed += delta
                    if phase == .work { study += delta }
                    delta = 0
                } else {
                    if phase == .work { study += remaining; cycles += 1 }
                    delta -= remaining
                    phase = nextPhase(after: phase, completedWork: cycles)
                    phaseElapsed = 0
                }
            }
        }
        return Reading(phase: phase, phaseElapsed: phaseElapsed, studySeconds: study,
                       completedWorkPhases: cycles, finished: finished)
    }

    private static func nextPhase(after phase: Phase, completedWork: Int) -> Phase {
        switch phase {
        case .work: return completedWork % 4 == 0 ? .longBreak : .shortBreak
        case .shortBreak, .longBreak: return .work
        }
    }

    private static func phaseLengthStatic(_ p: Phase, _ s: Snapshot) -> Double {
        switch p {
        case .work: return Double(s.workMinutes * 60)
        case .shortBreak: return Double(s.breakMinutes * 60)
        case .longBreak: return Double(s.longBreakMinutes * 60)
        }
    }

    private func phaseLength(_ p: Phase, _ s: Snapshot) -> Double { Self.phaseLengthStatic(p, s) }

    // MARK: - Private

    private func freezeBaseline() {
        let r = Self.project(snapshot, at: Date())
        var s = snapshot
        s.phase = r.phase
        s.phaseElapsed = r.phaseElapsed
        s.studySeconds = r.studySeconds
        s.completedWorkPhases = r.completedWorkPhases
        s.resumedAt = nil
        snapshot = s
        now = Date()
    }

    private func reset() {
        let s = snapshot
        snapshot = Snapshot(
            mode: s.mode, workMinutes: s.workMinutes, breakMinutes: s.breakMinutes,
            longBreakMinutes: s.longBreakMinutes, countdownMinutes: s.countdownMinutes
        )
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func createServerSession() async throws -> String {
        guard let api else { throw APIError.notLoggedIn }
        let resp = try await TimerRepository(api: api)
            .start(mode: snapshot.mode.sessionMode, planItemId: snapshot.item?.planItemId)
        return resp.sessionId
    }

    private func startTick() {
        stopTick()
        UIApplication.shared.isIdleTimerDisabled = true
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                self.now = Date()
                if self.reading.finished {
                    // タイマーモードの満了: 自動で一時停止し、記録を促す。
                    self.freezeBaseline()
                    self.stopTick()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    return
                }
            }
        }
    }

    private func stopTick() {
        tickTask?.cancel()
        tickTask = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    /// これから来るフェーズの切り替わりを最大 8 件まとめて予約する。
    /// アプリが裏にいても、休憩・作業の切り替えごとに通知が届く。
    private func scheduleNotifications() {
        cancelNotifications()
        let s = snapshot
        let base = Self.project(s, at: Date())
        switch s.mode {
        case .stopwatch:
            return
        case .timer:
            let remaining = Double(s.countdownMinutes * 60) - base.studySeconds
            guard remaining > 0 else { return }
            PushService.shared.scheduleLocal(after: remaining, title: "タイマー終了",
                                             body: "アプリを開いて学習を記録しましょう。",
                                             identifier: Self.notificationIds[0])
        case .pomodoro:
            var phase = base.phase
            var cycles = base.completedWorkPhases
            var offset = phaseLength(phase, s) - base.phaseElapsed
            for id in Self.notificationIds {
                let ended = phase
                if ended == .work { cycles += 1 }
                phase = Self.nextPhase(after: ended, completedWork: cycles)
                let body = ended == .work ? "\(phase.label)に入りましょう。" : "次の作業を始めましょう。"
                PushService.shared.scheduleLocal(after: offset, title: "\(ended.label)終了",
                                                 body: body, identifier: id)
                offset += phaseLength(phase, s)
            }
        }
    }

    private func cancelNotifications() {
        Self.notificationIds.forEach { PushService.shared.cancelLocal(identifier: $0) }
    }
}

extension Notification.Name {
    /// 学習記録・完了状態など、ホームの表示に影響する変更があったとき。
    static let studyDataDidChange = Notification.Name("studyDataDidChange")
    /// ログアウト (強制ログアウト含む) した直後。
    static let userDidSignOut = Notification.Name("userDidSignOut")
}
