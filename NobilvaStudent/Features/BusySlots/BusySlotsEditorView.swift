import SwiftUI

struct BusySlotsEditorView: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) var dismiss

    @State private var slots: [BusySlot] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            List {
                if slots.isEmpty && !isLoading {
                    ContentUnavailableView("設定なし", systemImage: "clock",
                                           description: Text("勉強に使えない時間帯を追加できます"))
                }
                ForEach(slots) { s in
                    row(s).swipeActions(edge: .trailing) {
                        if s.source == .individual {
                            Button(role: .destructive) { Task { await deleteSlot(s) } } label: {
                                Label("削除", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .navigationTitle("使えない時間")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .overlay { if isLoading && slots.isEmpty { ProgressView() } }
            .sheet(isPresented: $showAdd) {
                AddBusySlotSheet { title, kind, weekday, date, tod, notes in
                    Task { await add(title: title, kind: kind, weekday: weekday, date: date, tod: tod, notes: notes) }
                }
                .environmentObject(auth)
            }
            .errorAlert($errorMessage)
        }
    }

    private func row(_ s: BusySlot) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: s.source == .team ? "person.3.fill" : "person.fill")
                .foregroundStyle(Theme.secondaryLabel)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title)
                let sub = [s.isWeekly ? "毎週\(s.weekdayLabel)" : (s.specificDate ?? ""), s.timeOfDay.label]
                    .filter { !$0.isEmpty }.joined(separator: " ・ ")
                Text(sub).font(.caption).foregroundStyle(.secondary)
                if let n = s.notes, !n.isEmpty {
                    Text(n).font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            if s.source == .team {
                Toggle("", isOn: Binding(
                    get: { !(s.optedOut ?? false) },
                    set: { new in Task { await optOut(s, optOut: !new) } }
                ))
                .labelsHidden()
            }
        }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do { slots = try await BusySlotsRepository(api: auth.api).list() }
        catch let e as APIError { errorMessage = e.errorDescription }
        catch { errorMessage = "読み込みに失敗しました" }
    }

    private func add(title: String, kind: String, weekday: Int?, date: String?, tod: TimeOfDay, notes: String?) async {
        do {
            let body = BusySlotsRepository.CreateBody(
                title: title, kind: kind, weekday: weekday,
                specific_date: date, time_of_day: tod.rawValue, notes: notes
            )
            try await BusySlotsRepository(api: auth.api).create(body)
            await load()
        } catch let e as APIError { errorMessage = e.errorDescription }
        catch { errorMessage = "追加に失敗しました" }
    }

    private func deleteSlot(_ s: BusySlot) async {
        do { try await BusySlotsRepository(api: auth.api).delete(s.id); await load() }
        catch { errorMessage = "削除に失敗しました" }
    }

    private func optOut(_ s: BusySlot, optOut: Bool) async {
        do { try await BusySlotsRepository(api: auth.api).teamEventOptOut(s.id, optOut: optOut); await load() }
        catch { errorMessage = "更新に失敗しました" }
    }
}

private struct AddBusySlotSheet: View {
    @Environment(\.dismiss) var dismiss
    let onSubmit: (_ title: String, _ kind: String, _ weekday: Int?, _ date: String?, _ tod: TimeOfDay, _ notes: String?) -> Void

    @State private var title: String = ""
    @State private var kind: String = "weekly"
    @State private var weekday: Int = 1
    @State private var date: Date = Date()
    @State private var tod: TimeOfDay = .evening
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("タイトル") {
                    TextField("例: 部活 / 塾", text: $title)
                }
                Section("種別") {
                    Picker("種別", selection: $kind) {
                        Text("毎週").tag("weekly")
                        Text("単発").tag("once")
                    }.pickerStyle(.segmented)
                    if kind == "weekly" {
                        Picker("曜日", selection: $weekday) {
                            ForEach(0..<7, id: \.self) { w in
                                Text(["日","月","火","水","木","金","土"][w] + "曜").tag(w)
                            }
                        }
                    } else {
                        DatePicker("日付", selection: $date, displayedComponents: [.date])
                            .environment(\.locale, Locale(identifier: "ja_JP"))
                    }
                    Picker("時間帯", selection: $tod) {
                        ForEach(TimeOfDay.allCases) { t in Text(t.label).tag(t) }
                    }
                }
                Section("メモ (任意)") {
                    TextField("メモ", text: $notes, axis: .vertical).lineLimit(2...4)
                }
                Section {
                    Button {
                        onSubmit(
                            title.trimmingCharacters(in: .whitespaces),
                            kind,
                            kind == "weekly" ? weekday : nil,
                            kind == "once" ? JSTDate.iso.string(from: date) : nil,
                            tod,
                            notes.isEmpty ? nil : notes
                        )
                        dismiss()
                    } label: { Text("追加").bold().frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("使えない時間を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } } }
        }
    }
}
