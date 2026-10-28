import SwiftUI

/// タスクの追加 / 編集フォーム。`existing` が nil なら追加。
struct TaskFormView: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) var dismiss

    enum Outcome { case added, updated, deleted(id: String) }

    let existing: StudentTask?
    let onSaved: (Outcome) -> Void

    /// Web の科目色と同じ 5 教科 + その他。
    static let subjects = ["国語", "数学", "英語", "理科", "社会", "その他"]
    private static let weekdays = ["日", "月", "火", "水", "木", "金", "土"]

    @State private var title = ""
    @State private var subject = "その他"
    @State private var estimatedMinutes = 30
    @State private var hasDueDate = false
    @State private var dueDate = Date()
    @State private var hasScheduledDate = false
    @State private var scheduledDate = Date()
    @State private var recurrence: TaskRecurrence = .none
    @State private var weekday = 1
    @State private var timeOfDay: TimeOfDay?
    @State private var notes = ""
    @State private var hydrated = false
    /// 開いた直後のフォーム内容。これと違えば「変更あり」。
    @State private var initialBody: TasksRepository.TaskBody?

    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showDiscardConfirm = false
    @State private var showDeleteConfirm = false
    @FocusState private var titleFocused: Bool

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isDirty: Bool { existing == nil ? !trimmedTitle.isEmpty : hydrated && body0 != initialBody }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("やること (例: 数学ドリル p.20〜25)", text: $title)
                        .focused($titleFocused)
                        .submitLabel(.done)
                    Picker("科目", selection: $subject) {
                        ForEach(subjectOptions, id: \.self) { s in Text(s).tag(s) }
                    }
                    Picker("かかる時間", selection: $estimatedMinutes) {
                        ForEach(Array(stride(from: 5, through: 600, by: 5)), id: \.self) { m in
                            Text(formatMinutes(m)).tag(m)
                        }
                    }
                }
                Section {
                    Toggle("期限がある", isOn: $hasDueDate.animation())
                    if hasDueDate {
                        DatePicker("期限", selection: $dueDate, displayedComponents: [.date]).jst()
                    }
                    Toggle("やる日を決める", isOn: $hasScheduledDate.animation())
                    if hasScheduledDate {
                        DatePicker("やる日", selection: $scheduledDate, displayedComponents: [.date]).jst()
                    }
                } header: {
                    Text("いつやるか")
                }
                Section {
                    Picker("くり返し", selection: $recurrence) {
                        ForEach(TaskRecurrence.allCases) { r in Text(r.label).tag(r) }
                    }
                    if recurrence == .weekly {
                        Picker("曜日", selection: $weekday) {
                            ForEach(0..<7, id: \.self) { w in Text(Self.weekdays[w] + "曜").tag(w) }
                        }
                    }
                    Picker("時間帯", selection: $timeOfDay) {
                        Text("指定なし").tag(TimeOfDay?.none)
                        ForEach(TimeOfDay.allCases) { t in Text(t.label).tag(TimeOfDay?.some(t)) }
                    }
                }
                Section("メモ") {
                    TextField("メモ", text: $notes, axis: .vertical).lineLimit(2...5)
                }
                if existing != nil {
                    Section {
                        Button("タスクを削除", role: .destructive) { showDeleteConfirm = true }
                            .confirmationDialog("このタスクを削除しますか？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                                Button("削除", role: .destructive) { Task { await delete() } }
                            } message: {
                                Text("元に戻せません。")
                            }
                    }
                }
            }
            .navigationTitle(existing == nil ? "タスクを追加" : "タスクを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { isDirty ? (showDiscardConfirm = true) : dismiss() }
                        .confirmationDialog("変更を破棄しますか？", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                            Button("変更を破棄", role: .destructive) { dismiss() }
                        }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button(existing == nil ? "追加" : "保存") { Task { await save() } }
                            .disabled(trimmedTitle.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isDirty || isSaving)
            .onAppear {
                hydrate()
                if initialBody == nil { initialBody = body0 }
                if existing == nil { titleFocused = true }
            }
            .errorAlert($errorMessage)
        }
    }

    /// 既存タスクの科目が 5 教科以外でも選択肢から消えないようにする。
    private var subjectOptions: [String] {
        Self.subjects.contains(subject) ? Self.subjects : [subject] + Self.subjects
    }

    private func hydrate() {
        guard !hydrated else { return }
        defer { hydrated = true }
        guard let e = existing else { return }
        title = e.title
        subject = e.subject.isEmpty ? "その他" : e.subject
        estimatedMinutes = max(5, (e.estimatedMinutes / 5) * 5)
        if let d = e.dueDate.flatMap(JSTDate.date(from:)) { hasDueDate = true; dueDate = d }
        if let d = e.scheduledDate.flatMap(JSTDate.date(from:)) { hasScheduledDate = true; scheduledDate = d }
        recurrence = e.recurrence
        weekday = e.recurrenceWeekday ?? 1
        timeOfDay = e.preferredTimeOfDay
        notes = e.notes ?? ""
    }

    /// 送信する内容。講師が設定した分量や参考書の紐付けは、フォームに無いのでそのまま送り返す
    /// (サーバは未指定のキーを null で上書きするため)。
    private var body0: TasksRepository.TaskBody {
        let memo = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return TasksRepository.TaskBody(
            title: trimmedTitle,
            subject: subject,
            dueDate: hasDueDate ? JSTDate.iso.string(from: dueDate) : nil,
            estimatedMinutes: estimatedMinutes,
            unitCount: existing?.unitCount,
            unitLabel: existing?.unitLabel,
            goalId: existing?.goalId,
            recurrence: recurrence.rawValue,
            preferredTimeOfDay: timeOfDay?.rawValue,
            scheduledDate: hasScheduledDate ? JSTDate.iso.string(from: scheduledDate) : nil,
            notes: memo.isEmpty ? nil : memo,
            recurrenceWeekday: recurrence == .weekly ? weekday : nil
        )
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            if let existing {
                try await TasksRepository(api: auth.api).update(existing.id, body: body0)
            } else {
                _ = try await TasksRepository(api: auth.api).create(body0)
            }
            onSaved(existing == nil ? .added : .updated)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "保存できませんでした"
        }
    }

    private func delete() async {
        guard let existing else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await TasksRepository(api: auth.api).delete(existing.id)
            onSaved(.deleted(id: existing.id))
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "削除できませんでした"
        }
    }
}

private extension View {
    /// 日付は常に JST で選ばせる (端末のタイムゾーンが違っても 1 日ずれない)。
    func jst() -> some View {
        environment(\.timeZone, JSTDate.timeZone)
            .environment(\.calendar, JSTDate.calendar)
    }
}
