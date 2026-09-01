import SwiftUI

/// 新規/編集共通フォーム。`existing` が nil なら新規。
struct TaskFormView: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) var dismiss

    let existing: StudentTask?
    let onSaved: () -> Void

    @State private var title: String = ""
    @State private var subject: String = ""
    @State private var estimatedMinutes: Int = 30
    @State private var hasDueDate: Bool = false
    @State private var dueDate: Date = Date()
    @State private var hasScheduledDate: Bool = false
    @State private var scheduledDate: Date = Date()
    @State private var recurrence: TaskRecurrence = .none
    @State private var timeOfDay: TimeOfDay? = nil
    @State private var notes: String = ""

    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("基本") {
                    TextField("タイトル", text: $title)
                    TextField("科目", text: $subject)
                    Stepper("見積もり: \(estimatedMinutes) 分", value: $estimatedMinutes, in: 5...600, step: 5)
                }
                Section("期日 / いつやるか") {
                    Toggle("締切あり", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("締切", selection: $dueDate, displayedComponents: [.date])
                            .datePickerStyle(.compact)
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                    }
                    Toggle("実施予定日を指定", isOn: $hasScheduledDate)
                    if hasScheduledDate {
                        DatePicker("実施日", selection: $scheduledDate, displayedComponents: [.date])
                            .datePickerStyle(.compact)
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                    }
                }
                Section("繰り返し / 時間帯") {
                    Picker("繰り返し", selection: $recurrence) {
                        ForEach(TaskRecurrence.allCases) { r in Text(r.label).tag(r) }
                    }
                    Picker("時間帯", selection: $timeOfDay) {
                        Text("指定なし").tag(TimeOfDay?.none)
                        ForEach(TimeOfDay.allCases) { t in
                            Text(t.label).tag(TimeOfDay?.some(t))
                        }
                    }
                }
                Section("メモ") {
                    TextField("メモ", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle(existing == nil ? "タスク追加" : "タスク編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving { ProgressView() } else { Text("保存").bold() }
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { hydrate() }
            .errorAlert($errorMessage)
        }
    }

    private func hydrate() {
        guard let existing else { return }
        title = existing.title
        subject = existing.subject
        estimatedMinutes = existing.estimatedMinutes
        if let d = existing.dueDate, let date = JSTDate.date(from: d) {
            hasDueDate = true; dueDate = date
        }
        if let d = existing.scheduledDate, let date = JSTDate.date(from: d) {
            hasScheduledDate = true; scheduledDate = date
        }
        recurrence = existing.recurrence
        timeOfDay = existing.preferredTimeOfDay
        notes = existing.notes ?? ""
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }
        let body = TasksRepository.TaskBody(
            title: title.trimmingCharacters(in: .whitespaces),
            subject: subject.isEmpty ? nil : subject,
            dueDate: hasDueDate ? JSTDate.iso.string(from: dueDate) : nil,
            estimatedMinutes: estimatedMinutes,
            unitCount: nil, unitLabel: nil, goalId: nil,
            recurrence: recurrence.rawValue,
            preferredTimeOfDay: timeOfDay?.rawValue,
            scheduledDate: hasScheduledDate ? JSTDate.iso.string(from: scheduledDate) : nil,
            notes: notes.isEmpty ? nil : notes,
            recurrenceWeekday: nil
        )
        do {
            if let existing {
                try await TasksRepository(api: auth.api).update(existing.id, body: body)
            } else {
                _ = try await TasksRepository(api: auth.api).create(body)
            }
            onSaved()
            dismiss()
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "保存に失敗しました"
        }
    }
}
