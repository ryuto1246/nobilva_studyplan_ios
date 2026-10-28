import SwiftUI

/// 使えない時間 (マイページから push)。自分の予定は追加・削除、チームの予定は反映するかを切り替える。
struct BusySlotsEditorView: View {
    @EnvironmentObject var auth: AuthStore

    @State private var slots: [BusySlot] = []
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var errorMessage: String?
    @State private var showAdd = false
    /// チーム予定の opt-out を楽観的に反映する (id → 反映するか)。
    @State private var optOverrides: [String: Bool] = [:]

    private var visible: [BusySlot] {
        let today = JSTDate.todayString()
        // 過ぎた単発の予定は計画に影響しないので出さない。
        return slots.filter { $0.isWeekly || ($0.specificDate ?? "") >= today }
    }
    private var mine: [BusySlot] { visible.filter { $0.source == .individual } }
    private var team: [BusySlot] { visible.filter { $0.source == .team } }

    var body: some View {
        Group {
            if isLoading && slots.isEmpty {
                LoadingStateView()
            } else if loadFailed && slots.isEmpty {
                RetryStateView { await load() }
            } else {
                list
            }
        }
        .navigationTitle("使えない時間")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showAdd = true } label: { Label("追加", systemImage: "plus") }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showAdd) {
            AddBusySlotSheet { body in
                try await BusySlotsRepository(api: auth.api).create(body)
                await load()
            }
        }
        .errorAlert($errorMessage)
    }

    private var list: some View {
        List {
            Section {
                if mine.isEmpty {
                    Text("部活や塾など、勉強できない時間を登録しておくと、先生が計画を立てるときに避けてくれます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(mine) { s in
                    BusySlotRow(slot: s)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { Task { await deleteSlot(s) } } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text("自分の予定")
            }
            if !team.isEmpty {
                Section {
                    ForEach(team) { s in
                        Toggle(isOn: Binding(
                            get: { optOverrides[s.id] ?? !(s.optedOut ?? false) },
                            set: { new in Task { await setApplied(s, applied: new) } }
                        )) {
                            BusySlotRow(slot: s)
                        }
                    }
                } header: {
                    Text("チームの予定")
                } footer: {
                    Text("オフにすると、その予定は自分の計画に反映されません。")
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            slots = try await BusySlotsRepository(api: auth.api).list()
            optOverrides = [:]
            loadFailed = false
        } catch {
            loadFailed = true
            if !slots.isEmpty, (error as? APIError)?.isCancelled != true {
                errorMessage = (error as? APIError)?.errorDescription
            }
        }
    }

    private func deleteSlot(_ s: BusySlot) async {
        let snapshot = slots
        slots.removeAll { $0.id == s.id }
        do {
            try await BusySlotsRepository(api: auth.api).delete(s.id)
            NotificationCenter.default.post(name: .studyDataDidChange, object: nil)
        } catch {
            slots = snapshot
            errorMessage = (error as? APIError)?.errorDescription ?? "削除できませんでした"
        }
    }

    private func setApplied(_ s: BusySlot, applied: Bool) async {
        optOverrides[s.id] = applied
        do {
            try await BusySlotsRepository(api: auth.api).teamEventOptOut(s.id, optOut: !applied)
        } catch {
            optOverrides[s.id] = nil
            errorMessage = (error as? APIError)?.errorDescription ?? "更新できませんでした"
        }
    }
}

/// 予定 1 件 (タイトル・いつ・メモ)。
struct BusySlotRow: View {
    let slot: BusySlot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(slot.title)
            Text(slot.whenLabel).font(.subheadline).foregroundStyle(.secondary)
            if let team = slot.teamName, !team.isEmpty {
                Text(team).font(.caption).foregroundStyle(.tertiary)
            }
            if let n = slot.notes, !n.isEmpty {
                Text(n).font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

extension BusySlot {
    /// "毎週水曜 · 昼" / "10月9日(金) · 朝"
    var whenLabel: String {
        let day = isWeekly ? "毎週\(weekdayLabel)" : (specificDate.map(JSTDate.monthDay) ?? "")
        return [day, timeOfDay.label].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// 追加シート。保存が成功してから閉じる。
private struct AddBusySlotSheet: View {
    @Environment(\.dismiss) var dismiss
    let onSubmit: (BusySlotsRepository.CreateBody) async throws -> Void

    @State private var title = ""
    @State private var isWeekly = true
    @State private var weekday = 1
    @State private var date = Date()
    @State private var tod: TimeOfDay = .evening
    @State private var notes = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例: 部活、塾", text: $title)
                }
                Section {
                    Picker("くり返し", selection: $isWeekly) {
                        Text("毎週").tag(true)
                        Text("この日だけ").tag(false)
                    }
                    .pickerStyle(.segmented)
                    if isWeekly {
                        Picker("曜日", selection: $weekday) {
                            ForEach(0..<7, id: \.self) { w in
                                Text(["日", "月", "火", "水", "木", "金", "土"][w] + "曜").tag(w)
                            }
                        }
                    } else {
                        DatePicker("日付", selection: $date, in: Date()..., displayedComponents: [.date])
                            .environment(\.timeZone, JSTDate.timeZone)
                            .environment(\.calendar, JSTDate.calendar)
                    }
                    Picker("時間帯", selection: $tod) {
                        ForEach(TimeOfDay.allCases) { t in Text(t.label).tag(t) }
                    }
                }
                Section("メモ (任意)") {
                    TextField("メモ", text: $notes, axis: .vertical).lineLimit(2...4)
                }
            }
            .navigationTitle("使えない時間を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button("追加") { Task { await save() } }.disabled(trimmedTitle.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSaving)
            .errorAlert($errorMessage)
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        let memo = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = BusySlotsRepository.CreateBody(
            title: trimmedTitle,
            kind: isWeekly ? "weekly" : "date",
            weekday: isWeekly ? weekday : nil,
            specific_date: isWeekly ? nil : JSTDate.iso.string(from: date),
            time_of_day: tod.rawValue,
            notes: memo.isEmpty ? nil : memo
        )
        do {
            try await onSubmit(body)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "追加できませんでした"
        }
    }
}
