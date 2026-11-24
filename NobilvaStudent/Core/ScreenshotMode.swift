#if DEBUG
import Foundation

/// App Store 用スクリーンショットの撮影モード (Debug ビルド限定)。
///
/// 起動引数に `-ScreenshotMode` を付けると、ログインを飛ばして見本の生徒として起動し、
/// API への通信をすべて `ScreenshotURLProtocol` が見本データで返す。本番には一切つながない。
///
/// ```
/// xcrun simctl launch <udid> com.nobilva.app -ScreenshotMode
/// xcrun simctl launch <udid> com.nobilva.app -ScreenshotMode -ScreenshotTimer  # タイマー計測中から始める
/// ```
///
/// 日付は「今日」からの相対で作るので、いつ撮っても同じ見た目になる。
enum ScreenshotMode {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-ScreenshotMode")

    static let studentId = "screenshot-student"
    static let teacherId = "screenshot-teacher"
    static let threadId = "screenshot-thread"
    static let studentName = "田中 悠真"
    static let teacherName = "佐藤 健太"

    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ScreenshotURLProtocol.self]
        return URLSession(configuration: config)
    }()

    /// 撮影モードのタイマーは毎回まっさらから始める (前回の計測を持ち越さない)。
    /// `-ScreenshotTimer` のときだけ、数学ドリルを 12 分ほど計測中にする。
    @MainActor
    static var timerSnapshot: StudyTimer.Snapshot? {
        guard isEnabled else { return nil }
        var s = StudyTimer.Snapshot()
        guard ProcessInfo.processInfo.arguments.contains("-ScreenshotTimer") else { return s }
        s.phaseElapsed = 742
        s.studySeconds = 742
        s.resumedAt = Date()
        s.item = .init(planItemId: "item-0-1", title: "数学基礎ドリル（20問）", subject: "数学")
        s.sessionId = "screenshot-session"
        s.startedAt = Date().addingTimeInterval(-742)
        return s
    }
}

/// API リクエストを横取りして見本データを返す。書き込み系は成功だけ返す。
final class ScreenshotURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let data = (try? JSONSerialization.data(withJSONObject: ["data": ScreenshotFixtures.response(method: method, path: path)])) ?? Data()
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// 見本データ。JSON はサーバと同じ形 (snake_case / chat だけ camelCase)。
enum ScreenshotFixtures {
    static func response(method: String, path: String) -> Any {
        let p = path.replacingOccurrences(of: "/api/v1/student", with: "")
        switch (method, p) {
        case ("GET", "/dashboard/summary"): return dashboard
        case ("GET", "/plan/periods"): return [period]
        case ("GET", "/plan"): return day(0)
        case ("GET", "/tasks/unscheduled"), ("GET", "/tasks/overdue"): return [Any]()
        case ("GET", "/sessions"): return sessions
        case ("GET", "/chat/threads"): return [thread]
        case ("GET", "/chat/partners"): return [partner]
        case ("GET", "/chat/unread/total"): return ["total": 0]
        case ("GET", "/chat/\(ScreenshotMode.threadId)/messages"): return messages
        case ("GET", "/chat/\(ScreenshotMode.threadId)/read"): return ["teacher_last_read_at": timestamp(-1, "21:40")]
        case ("POST", "/chat/threads"): return ["thread_id": ScreenshotMode.threadId]
        case ("GET", "/meetings/upcoming"): return meeting
        case ("GET", "/meetings"): return [meeting]
        case ("GET", "/profile/student"): return studentProfile
        case ("GET", "/profile/user-info"): return userInfo
        case ("GET", "/settings/notifications"):
            return ["chat_notifications": true, "meeting_reminders": true, "meeting_reminder_minutes": 30]
        case ("GET", "/busy-slots"): return [Any]()
        case ("POST", "/sessions/start"): return ["session_id": "screenshot-session"]
        default:
            if method == "POST", p.hasSuffix("/messages") { return ["message_id": UUID().uuidString] }
            if p.hasPrefix("/meetings/") { return meeting }
            return [String: Any]()
        }
    }

    // MARK: - 計画

    /// 日ごとの計画: (タイトル, 科目, 開始時刻, 分, 完了か)。
    /// 0 = 今日。前日までは全部完了にして「N日遅れ」を出さない。
    private static let plans: [Int: [(String, String, String, Int, Bool)]] = [
        -1: [("英単語ルーティン（30個）", "英語", "07:00", 20, true),
             ("数学 二次関数の復習（15問）", "数学", "17:30", 40, true),
             ("古文単語の確認", "国語", "20:30", 30, true)],
        0: [("英単語ルーティン（30個）", "英語", "07:00", 20, true),
            ("数学基礎ドリル（20問）", "数学", "17:30", 45, false),
            ("化学基礎 問題演習（10問）", "理科", "19:30", 40, false),
            ("歴史 年号まとめ", "社会", "21:00", 30, false)],
        1: [("英単語ルーティン（30個）", "英語", "07:00", 20, false),
            ("英語長文読解", "英語", "17:30", 40, false),
            ("数学基礎ドリル（20問）", "数学", "20:00", 45, false)],
        2: [("英単語ルーティン（30個）", "英語", "07:00", 20, false),
            ("現代文 問題演習", "国語", "20:00", 45, false)],
        3: [("英単語ルーティン（30個）", "英語", "07:00", 20, false),
            ("化学基礎 問題演習（10問）", "理科", "17:30", 40, false),
            ("数学 二次関数の応用（10問）", "数学", "20:00", 50, false)],
        4: [("英単語ルーティン（30個）", "英語", "07:00", 20, false),
            ("地理 用語の確認", "社会", "20:30", 30, false)],
        5: [("数学 週のまとめテスト", "数学", "10:00", 60, false),
            ("英語長文読解", "英語", "14:00", 40, false),
            ("古文 文法の復習", "国語", "16:00", 30, false)],
    ]

    private static func day(_ offset: Int) -> [String: Any] {
        let date = JSTDate.todayString(offsetDays: offset)
        let planId = "plan-\(offset)"
        let items: [[String: Any]] = (plans[offset] ?? []).enumerated().map { i, p in
            ["id": "item-\(offset)-\(i)", "plan_id": planId, "task_id": NSNull(), "goal_id": NSNull(),
             "title": p.0, "subject": p.1, "start_time": p.2 + ":00", "duration_minutes": p.3,
             "status": p.4 ? "completed" : "pending", "rationale": NSNull(), "sort_order": i]
        }
        return ["plan": ["id": planId, "student_id": ScreenshotMode.studentId, "plan_date": date,
                         "plan_type": "weekly", "period_id": "period-1", "created_at": NSNull()],
                "items": items]
    }

    private static var period: [String: Any] {
        ["period": ["id": "period-1", "student_id": ScreenshotMode.studentId,
                    "start_date": JSTDate.todayString(offsetDays: -1),
                    "end_date": JSTDate.todayString(offsetDays: 5),
                    "title": NSNull(), "created_at": NSNull()],
         "days": plans.keys.sorted().map(day)]
    }

    private static var dashboard: [String: Any] {
        ["profile": ["display_name": ScreenshotMode.studentName, "ai_plan_enabled": false],
         "today": ["date": JSTDate.todayString(), "plan": day(0)],
         "tomorrow": ["date": JSTDate.todayString(offsetDays: 1), "plan": day(1)],
         "overdue_tasks": [Any](),
         "chat_partners": [partner],
         "busy_slots": [Any](),
         "upcoming_meeting": meeting]
    }

    // MARK: - 学習記録

    /// 直近 7 日の学習時間 (分)。最後が今日 (朝の英単語の分)。
    private static let minutesByDay = [65, 80, 45, 95, 70, 110, 20]

    private static var sessions: [[String: Any]] {
        minutesByDay.enumerated().map { i, minutes in
            let offset = i - (minutesByDay.count - 1)
            return ["id": "session-\(i)", "plan_item_id": offset == 0 ? "item-0-0" : NSNull(),
                    "started_at": timestamp(offset, "07:00"), "ended_at": NSNull(),
                    "duration_seconds": minutes * 60, "mode": "timer"]
        }
    }

    // MARK: - 面談

    private static var meeting: [String: Any] {
        ["id": "meeting-1", "series_id": NSNull(), "teacher_id": ScreenshotMode.teacherId,
         "student_id": ScreenshotMode.studentId, "created_by": ScreenshotMode.teacherId,
         "title": "月次面談", "meeting_url": NSNull(), "notes": NSNull(),
         "scheduled_start_at": timestamp(2, "19:00"), "scheduled_end_at": timestamp(2, "19:30"),
         "status": "scheduled", "reschedule_state": "none", "reschedule_actor": NSNull(),
         "reschedule_note": NSNull(), "proposed_start_at": NSNull(), "proposed_end_at": NSNull(),
         "teacher": ["id": ScreenshotMode.teacherId, "display_name": ScreenshotMode.teacherName],
         "student": ["id": ScreenshotMode.studentId, "display_name": ScreenshotMode.studentName]]
    }

    // MARK: - チャット

    private static var partner: [String: Any] {
        ["teacherId": ScreenshotMode.teacherId, "displayName": ScreenshotMode.teacherName]
    }

    /// (自分が送ったか, 何日前か, 時刻, 本文)。
    private static let conversation: [(Bool, Int, String, String)] = [
        (false, -2, "18:40", "今週の計画を作りました。部活のある日は、夜に40分くらいで終わるようにしています。"),
        (true, -2, "19:02", "確認しました。英単語は朝にやるようにします。"),
        (false, -2, "19:10", "いいですね。朝の20分を続けられると力になります。"),
        (true, -1, "20:12", "::task::{\"title\":\"数学基礎ドリル（20問）\",\"subject\":\"数学\",\"amount\":\"20問\"}\n\n来週は部活の大会があって、ドリルを全部やるのが難しそうです。"),
        (false, -1, "20:25", "大会前は無理をしなくて大丈夫です。来週は20問を10問に減らして、残りは大会のあとに回しましょう。計画も直しておきます。"),
        (true, -1, "20:31", "ありがとうございます。助かります！"),
        (false, -1, "21:05", "計画を更新しました。大会、がんばってください。終わったら、次の面談で一緒に見直しましょう。"),
        (true, -1, "21:18", "はい、がんばります。"),
    ]

    private static var messages: [[String: Any]] {
        conversation.enumerated().map { i, m in
            ["id": "message-\(i)", "threadId": ScreenshotMode.threadId,
             "senderId": m.0 ? ScreenshotMode.studentId : ScreenshotMode.teacherId,
             "senderName": m.0 ? ScreenshotMode.studentName : ScreenshotMode.teacherName,
             "body": m.3, "imageUrl": NSNull(), "isAdminMessage": false,
             "createdAt": timestamp(m.1, m.2)]
        }
    }

    private static var thread: [String: Any] {
        let last = conversation.last!
        return ["id": ScreenshotMode.threadId, "teacherId": ScreenshotMode.teacherId,
                "teacherName": ScreenshotMode.teacherName, "studentId": ScreenshotMode.studentId,
                "studentName": ScreenshotMode.studentName, "lastMessageAt": timestamp(last.1, last.2),
                "lastMessageBody": last.3, "unreadCount": 0]
    }

    // MARK: - プロフィール

    private static var studentProfile: [String: Any] {
        ["id": "student-profile-1", "user_id": ScreenshotMode.studentId, "grade_level": "high",
         "daily_available_minutes": 120, "pomodoro_work_minutes": 25, "pomodoro_break_minutes": 5,
         "pomodoro_long_break_minutes": 15, "invite_code": NSNull(), "ai_plan_enabled": false,
         "tags": [Any]()]
    }

    private static var userInfo: [String: Any] {
        ["profile": ["id": ScreenshotMode.studentId, "role": "student",
                     "display_name": ScreenshotMode.studentName, "avatar_url": NSNull(),
                     "onboarding_completed": true, "must_change_password": false, "created_at": NSNull()],
         "student": studentProfile,
         "email": "student@example.com"]
    }

    // MARK: - Helpers

    /// 今日から offset 日の JST "HH:mm" を ISO8601 にする。
    private static func timestamp(_ offset: Int, _ time: String) -> String {
        "\(JSTDate.todayString(offsetDays: offset))T\(time):00+09:00"
    }
}
#endif
