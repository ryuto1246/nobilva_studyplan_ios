import SwiftUI
import UIKit

struct SettingsIndexView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var showLogoutConfirm = false

    static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "-"
        let build = info?["CFBundleVersion"] as? String ?? "-"
        return "\(version) (\(build))"
    }()

    var body: some View {
        NavigationStack {
            List {
                Section("プロフィール") {
                    NavigationLink { AccountView().environmentObject(auth) } label: {
                        Label("アカウント", systemImage: "person.crop.circle")
                    }
                    NavigationLink { StudySettingsView().environmentObject(auth) } label: {
                        Label("学習設定", systemImage: "graduationcap")
                    }
                    NavigationLink { PomodoroSettingsView().environmentObject(auth) } label: {
                        Label("ポモドーロ", systemImage: "timer")
                    }
                }
                Section("通知") {
                    NavigationLink { NotificationsSettingsView().environmentObject(auth) } label: {
                        Label("通知設定", systemImage: "bell")
                    }
                }
                Section("セキュリティ") {
                    NavigationLink { SecuritySettingsView().environmentObject(auth) } label: {
                        Label("パスキー / パスワード", systemImage: "lock.shield")
                    }
                }
                Section("ヘルプ") {
                    NavigationLink { GuideView() } label: {
                        Label("使い方", systemImage: "questionmark.circle")
                    }
                }
                Section("利用規約・プライバシー") {
                    if let url = URL(string: "https://nectere.jp/ja/legal/nobilva/terms-of-service") {
                        Link(destination: url) {
                            Label("利用規約", systemImage: "doc.text")
                        }
                    }
                    if let url = URL(string: "https://nectere.jp/ja/legal/privacy-policy") {
                        Link(destination: url) {
                            Label("プライバシーポリシー", systemImage: "hand.raised")
                        }
                    }
                    if let url = URL(string: "https://nectere.jp/ja/legal/nobilva/commercial-disclosure") {
                        Link(destination: url) {
                            Label("特定商取引法に基づく表記", systemImage: "doc.plaintext")
                        }
                    }
                }
                Section {
                    Button(role: .destructive) {
                        showLogoutConfirm = true
                    } label: {
                        Label("ログアウト", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    if let url = URL(string: "https://studyplan.nobilva.jp/settings/account/delete") {
                        Link(destination: url) {
                            Label("アカウントを削除する (Web)", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                }
                Section {
                    HStack {
                        Text("バージョン")
                        Spacer()
                        Text(Self.appVersion).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("設定")
            .confirmationDialog("ログアウトしますか？", isPresented: $showLogoutConfirm, titleVisibility: .visible) {
                Button("ログアウト", role: .destructive) { Task { await auth.logout() } }
            }
        }
    }
}

// MARK: - Sub pages

struct AccountView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var info: StudentUserInfo?
    @State private var isLoading = false

    var body: some View {
        List {
            if let info {
                Section("表示名") {
                    Text(info.profile.displayName)
                }
                Section("メールアドレス") {
                    Text(info.email ?? "-")
                }
                if let student = info.student {
                    Section("招待コード (講師向け)") {
                        HStack {
                            Text(student.inviteCode ?? "-").monospaced()
                            Spacer()
                            if let code = student.inviteCode {
                                Button {
                                    UIPasteboard.general.string = code
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                            }
                        }
                    }
                }
            } else if isLoading {
                ProgressView()
            }
        }
        .navigationTitle("アカウント")
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        info = try? await SettingsRepository(api: auth.api).userInfo()
    }
}

struct StudySettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var info: StudentUserInfo?
    @State private var grade: GradeLevel = .high
    @State private var minutes: Int = 120
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedFlag = false

    var body: some View {
        Form {
            Section("学年") {
                Picker("学年", selection: $grade) {
                    ForEach(GradeLevel.allCases) { g in Text(g.label).tag(g) }
                }
            }
            Section("1 日の学習可能時間") {
                Stepper("\(minutes) 分", value: $minutes, in: 15...720, step: 15)
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if isSaving { ProgressView() }
                        Text("保存").bold()
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
            if savedFlag {
                Section { Text("保存しました").foregroundStyle(.green) }
            }
        }
        .navigationTitle("学習設定")
        .task { await load() }
        .refreshable { await load() }
        .errorAlert($errorMessage)
    }

    private func load() async {
        info = try? await SettingsRepository(api: auth.api).userInfo()
        if let s = info?.student {
            grade = s.gradeLevel ?? .high
            minutes = s.dailyAvailableMinutes
        }
    }

    private func save() async {
        errorMessage = nil; savedFlag = false
        isSaving = true; defer { isSaving = false }
        do {
            try await SettingsRepository(api: auth.api).patchProfile(.init(display_name: nil, grade_level: grade.rawValue, daily_minutes: minutes))
            savedFlag = true
        } catch let e as APIError { errorMessage = e.errorDescription }
        catch { errorMessage = "保存に失敗しました" }
    }
}

struct PomodoroSettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var work: Int = 25
    @State private var short: Int = 5
    @State private var long: Int = 15
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedFlag = false

    var body: some View {
        Form {
            Section("作業時間") { Stepper("\(work) 分", value: $work, in: 5...90, step: 5) }
            Section("短い休憩") { Stepper("\(short) 分", value: $short, in: 1...30, step: 1) }
            Section("長い休憩") { Stepper("\(long) 分", value: $long, in: 5...60, step: 5) }
            Section {
                Button { Task { await save() } } label: {
                    HStack { if isSaving { ProgressView() }; Text("保存").bold() }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).disabled(isSaving)
            }
            if let errorMessage { Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) } }
            if savedFlag { Section { Text("保存しました").foregroundStyle(.green) } }
        }
        .navigationTitle("ポモドーロ")
        .task { await load() }
        .refreshable { await load() }
        .errorAlert($errorMessage)
    }

    private func load() async {
        if let info = try? await SettingsRepository(api: auth.api).userInfo(), let s = info.student {
            work = s.pomodoroWorkMinutes
            short = s.pomodoroBreakMinutes
            long = s.pomodoroLongBreakMinutes
        }
    }

    private func save() async {
        errorMessage = nil; savedFlag = false
        isSaving = true; defer { isSaving = false }
        do {
            try await SettingsRepository(api: auth.api).patchPomodoro(.init(work_minutes: work, break_minutes: short, long_break_minutes: long))
            savedFlag = true
        } catch let e as APIError { errorMessage = e.errorDescription }
        catch { errorMessage = "保存に失敗しました" }
    }
}

struct NotificationsSettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var prefs = NotificationPreferences(morningReminder: false, morningReminderTime: "07:30", planReminders: false, planReminderMinutes: 10, eveningSummary: false, eveningSummaryTime: "22:00", streakAlerts: false, quietHoursStart: nil, quietHoursEnd: nil, meetingReminders: true, meetingReminderMinutes: 30)
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var savedFlag = false

    var body: some View {
        Form {
            Section {
                Toggle("朝のやる気メッセージ", isOn: Binding(get: { prefs.morningReminder ?? false }, set: { new in prefs = replace(prefs, morningReminder: new) }))
                Toggle("計画の直前リマインド", isOn: Binding(get: { prefs.planReminders ?? false }, set: { new in prefs = replace(prefs, planReminders: new) }))
                Toggle("夜のサマリー", isOn: Binding(get: { prefs.eveningSummary ?? false }, set: { new in prefs = replace(prefs, eveningSummary: new) }))
                Toggle("ストリーク切れ警告", isOn: Binding(get: { prefs.streakAlerts ?? false }, set: { new in prefs = replace(prefs, streakAlerts: new) }))
            }
            Section("面談・個別指導") {
                Toggle("開始前に通知", isOn: Binding(
                    get: { prefs.meetingReminders ?? true },
                    set: { new in prefs = replace(prefs, meetingReminders: new) }
                ))
                if prefs.meetingReminders ?? true {
                    Stepper(value: Binding(
                        get: { prefs.meetingReminderMinutes ?? 30 },
                        set: { new in prefs = replace(prefs, meetingReminderMinutes: new) }
                    ), in: 0...240, step: 5) {
                        Text("通知タイミング: \((prefs.meetingReminderMinutes ?? 30) == 0 ? "開始時" : "\(prefs.meetingReminderMinutes ?? 30) 分前")")
                    }
                }
            }
            Section {
                Text("※ 通知はこの端末のプッシュ通知で届きます。iPhone の設定アプリで Nobilva の通知を許可しておいてください。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button { Task { await save() } } label: {
                    HStack { if isSaving { ProgressView() }; Text("保存").bold() }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).disabled(isSaving)
            }
            if let errorMessage { Section { Text(errorMessage).font(.footnote).foregroundStyle(.red) } }
            if savedFlag { Section { Text("保存しました").foregroundStyle(.green) } }
        }
        .navigationTitle("通知設定")
        .task { await load() }
        .refreshable { await load() }
        .errorAlert($errorMessage)
    }

    private func replace(_ p: NotificationPreferences,
                         morningReminder: Bool? = nil, planReminders: Bool? = nil,
                         eveningSummary: Bool? = nil, streakAlerts: Bool? = nil,
                         meetingReminders: Bool? = nil, meetingReminderMinutes: Int? = nil) -> NotificationPreferences {
        NotificationPreferences(
            morningReminder: morningReminder ?? p.morningReminder,
            morningReminderTime: p.morningReminderTime,
            planReminders: planReminders ?? p.planReminders,
            planReminderMinutes: p.planReminderMinutes,
            eveningSummary: eveningSummary ?? p.eveningSummary,
            eveningSummaryTime: p.eveningSummaryTime,
            streakAlerts: streakAlerts ?? p.streakAlerts,
            quietHoursStart: p.quietHoursStart,
            quietHoursEnd: p.quietHoursEnd,
            meetingReminders: meetingReminders ?? p.meetingReminders,
            meetingReminderMinutes: meetingReminderMinutes ?? p.meetingReminderMinutes
        )
    }

    private func load() async {
        if let p = try? await SettingsRepository(api: auth.api).notifications() { prefs = p }
    }

    private func save() async {
        errorMessage = nil; savedFlag = false
        isSaving = true; defer { isSaving = false }
        do {
            try await SettingsRepository(api: auth.api).patchNotifications(.init(
                morning_reminder: prefs.morningReminder,
                morning_reminder_time: prefs.morningReminderTime,
                plan_reminders: prefs.planReminders,
                plan_reminder_minutes: prefs.planReminderMinutes,
                evening_summary: prefs.eveningSummary,
                evening_summary_time: prefs.eveningSummaryTime,
                streak_alerts: prefs.streakAlerts,
                quiet_hours_start: prefs.quietHoursStart,
                quiet_hours_end: prefs.quietHoursEnd,
                meeting_reminders: prefs.meetingReminders,
                meeting_reminder_minutes: prefs.meetingReminderMinutes
            ))
            savedFlag = true
        } catch let e as APIError { errorMessage = e.errorDescription }
        catch { errorMessage = "保存に失敗しました" }
    }
}

struct SecuritySettingsView: View {
    @EnvironmentObject var auth: AuthStore
    var body: some View {
        List {
            Section {
                NavigationLink {
                    PasskeyManagementView().environmentObject(auth)
                } label: {
                    Label("パスキー", systemImage: "faceid")
                }
                NavigationLink {
                    PasswordChangeView().environmentObject(auth)
                } label: {
                    Label("パスワード", systemImage: "key.fill")
                }
            } footer: {
                Text("普段はパスキー (Face ID) でログインし、パスワードはバックアップとして設定しておくのがおすすめです。")
            }
        }
        .navigationTitle("セキュリティ")
    }
}
