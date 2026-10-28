import SwiftUI
import UIKit
import UserNotifications

// マイページ > 設定 の各画面。
// 共通ルール:
//  - 読み込みに失敗したら初期値のフォームを出さない (初期値で上書き保存する事故を防ぐ)
//  - 保存はナビゲーションバー右上。変更が無いときは押せない。成功したら前の画面へ戻る

/// 設定フォームの読み込み・保存の枠。各画面は中身のフォームだけを書く。
private struct SettingsForm<Content: View>: View {
    let title: String
    let isDirty: Bool
    let load: () async throws -> Void
    let save: () async throws -> Void
    @ViewBuilder let content: () -> Content

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading
    @State private var isSaving = false
    @State private var errorMessage: String?

    enum Phase { case loading, loaded, failed }

    var body: some View {
        Group {
            switch phase {
            case .loading: LoadingStateView()
            case .failed: RetryStateView { await runLoad() }
            case .loaded: Form { content() }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("保存") { Task { await runSave() } }
                        .disabled(phase != .loaded || !isDirty)
                }
            }
        }
        .task { if phase == .loading { await runLoad() } }
        .errorAlert($errorMessage)
    }

    private func runLoad() async {
        phase = .loading
        do { try await load(); phase = .loaded } catch { phase = .failed }
    }

    private func runSave() async {
        isSaving = true
        defer { isSaving = false }
        do {
            try await save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "保存できませんでした"
        }
    }
}

// MARK: - アカウント

struct AccountView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var info: StudentUserInfo?
    @State private var student: StudentProfile?
    @State private var loadFailed = false
    @State private var copied = false

    var body: some View {
        Group {
            if let info {
                List {
                    Section {
                        LabeledContent("表示名", value: info.profile.displayName)
                        LabeledContent("メールアドレス", value: info.email ?? "未登録")
                    }
                    if let code = student?.inviteCode {
                        Section {
                            Button {
                                UIPasteboard.general.string = code
                                copied = true
                            } label: {
                                LabeledContent("招待コード") {
                                    HStack(spacing: 6) {
                                        Text(code).monospaced()
                                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                                    }
                                }
                            }
                            .foregroundStyle(Color.primary)
                            .sensoryFeedback(.success, trigger: copied)
                            .accessibilityHint("タップでコピーします")
                        } footer: {
                            Text("保護者の方を招待するときに使います。タップでコピーできます。")
                        }
                    }
                }
            } else if loadFailed {
                RetryStateView { await load() }
            } else {
                LoadingStateView()
            }
        }
        .navigationTitle("アカウント")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        loadFailed = false
        let repo = SettingsRepository(api: auth.api)
        do {
            async let i = repo.userInfo()
            async let s = try? repo.studentProfile()
            info = try await i
            student = await s
        } catch {
            loadFailed = true
        }
    }
}

// MARK: - 学年・学習時間

struct StudySettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var original: StudentProfile?
    @State private var grade: GradeLevel = .high
    @State private var minutes: Int = 120

    private var isDirty: Bool {
        guard let o = original else { return false }
        return o.gradeLevel != grade || o.dailyAvailableMinutes != minutes
    }

    var body: some View {
        SettingsForm(title: "学年・学習時間", isDirty: isDirty, load: load, save: save) {
            Section {
                Picker("学年", selection: $grade) {
                    ForEach(GradeLevel.allCases) { g in Text(g.label).tag(g) }
                }
            }
            Section {
                Picker("1日に勉強できる時間", selection: $minutes) {
                    ForEach(Array(stride(from: 15, through: 720, by: 15)), id: \.self) { m in
                        Text(formatMinutes(m)).tag(m)
                    }
                }
            } footer: {
                Text("先生が計画を立てるときの目安になります。")
            }
        }
    }

    private func load() async throws {
        let s = try await SettingsRepository(api: auth.api).studentProfile()
        original = s
        grade = s.gradeLevel ?? .high
        // 15 分刻みの選択肢に丸める。
        minutes = min(720, max(15, (s.dailyAvailableMinutes / 15) * 15))
    }

    private func save() async throws {
        try await SettingsRepository(api: auth.api)
            .patchProfile(.init(display_name: nil, grade_level: grade.rawValue, daily_minutes: minutes))
    }
}

// MARK: - ポモドーロ

struct PomodoroSettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var original: StudentProfile?
    @State private var work = 25
    @State private var short = 5
    @State private var long = 15

    private var isDirty: Bool {
        guard let o = original else { return false }
        return o.pomodoroWorkMinutes != work || o.pomodoroBreakMinutes != short || o.pomodoroLongBreakMinutes != long
    }

    var body: some View {
        SettingsForm(title: "ポモドーロ", isDirty: isDirty, load: load, save: save) {
            Section {
                Stepper("作業 \(work)分", value: $work, in: 5...90, step: 5)
                Stepper("休憩 \(short)分", value: $short, in: 1...30)
                Stepper("長い休憩 \(long)分", value: $long, in: 5...60, step: 5)
            } footer: {
                Text("作業を 4 回終えるごとに長い休憩になります。計測中のタイマーには、次に開始したときから反映されます。")
            }
        }
    }

    private func load() async throws {
        let s = try await SettingsRepository(api: auth.api).studentProfile()
        original = s
        work = s.pomodoroWorkMinutes
        short = s.pomodoroBreakMinutes
        long = s.pomodoroLongBreakMinutes
    }

    private func save() async throws {
        try await SettingsRepository(api: auth.api)
            .patchPomodoro(.init(work_minutes: work, break_minutes: short, long_break_minutes: long))
    }
}

// MARK: - 通知

struct NotificationsSettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var original: NotificationPreferences?
    @State private var prefs = NotificationPreferences.defaults
    @State private var systemDenied = false

    private var isDirty: Bool { original != nil && original != prefs }

    var body: some View {
        SettingsForm(title: "通知", isDirty: isDirty, load: load, save: save) {
            if systemDenied {
                Section {
                    Button("iPhone の設定で通知を許可する") {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                } footer: {
                    Text("通知がオフになっているため、ここで設定しても届きません。")
                }
            }
            Section {
                Toggle("チャットの新着", isOn: Binding(
                    get: { prefs.chatNotifications ?? false },
                    set: { prefs.chatNotifications = $0 }
                ))
            }
            Section {
                Toggle("面談の前に知らせる", isOn: Binding(
                    get: { prefs.meetingReminders ?? true },
                    set: { prefs.meetingReminders = $0 }
                ))
                if prefs.meetingReminders ?? true {
                    Picker("タイミング", selection: Binding(
                        get: { prefs.meetingReminderMinutes ?? 30 },
                        set: { prefs.meetingReminderMinutes = $0 }
                    )) {
                        ForEach([0, 10, 30, 60, 120, 1440], id: \.self) { m in
                            Text(m == 0 ? "開始時" : m == 1440 ? "前日" : "\(formatMinutes(m))前").tag(m)
                        }
                    }
                }
            } header: {
                Text("面談")
            }
        }
    }

    private func load() async throws {
        let p = try await SettingsRepository(api: auth.api).notifications()
        let resolved = NotificationPreferences(
            chatNotifications: p?.chatNotifications ?? NotificationPreferences.defaults.chatNotifications,
            meetingReminders: p?.meetingReminders ?? NotificationPreferences.defaults.meetingReminders,
            meetingReminderMinutes: p?.meetingReminderMinutes ?? NotificationPreferences.defaults.meetingReminderMinutes
        )
        original = resolved
        prefs = resolved
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        systemDenied = settings.authorizationStatus == .denied
    }

    private func save() async throws {
        try await SettingsRepository(api: auth.api).patchNotifications(.init(
                chatNotifications: prefs.chatNotifications ?? false,
                meetingReminders: prefs.meetingReminders ?? true,
                meetingReminderMinutes: prefs.meetingReminderMinutes ?? 30
        ))
    }
}

// MARK: - パスキー・パスワード

struct SecuritySettingsView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { PasskeyManagementView() } label: {
                    Label("パスキー", systemImage: "person.badge.key")
                }
                NavigationLink { PasswordChangeView() } label: {
                    Label("パスワード", systemImage: "key")
                }
            } footer: {
                Text("普段はパスキー (Face ID / Touch ID) でログインし、パスワードは予備として設定しておくのがおすすめです。")
            }
        }
        .navigationTitle("パスキー・パスワード")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - アカウント削除

struct DeleteAccountView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var confirmText = ""
    @State private var isDeleting = false
    @State private var errorMessage: String?

    private let phrase = "削除する"

    var body: some View {
        Form {
            Section {
                Text("アカウントを削除すると、計画・学習記録・チャットなどのデータがすべて消え、元に戻せません。")
            }
            Section {
                TextField(phrase, text: $confirmText)
                    .autocorrectionDisabled()
            } header: {
                Text("確認のため「\(phrase)」と入力してください")
            }
            Section {
                Button(role: .destructive) {
                    Task { await delete() }
                } label: {
                    HStack {
                        if isDeleting { ProgressView() }
                        Text("アカウントを削除")
                    }
                }
                .disabled(confirmText != phrase || isDeleting)
            }
        }
        .navigationTitle("アカウントを削除")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert($errorMessage)
    }

    private struct ConfirmBody: Encodable { let confirm: String }

    private func delete() async {
        isDeleting = true
        defer { isDeleting = false }
        do {
            let _: EmptyResponse = try await auth.api.delete("/api/v1/student/account", body: ConfirmBody(confirm: phrase))
            await auth.clearForLogout()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "削除できませんでした"
        }
    }
}
