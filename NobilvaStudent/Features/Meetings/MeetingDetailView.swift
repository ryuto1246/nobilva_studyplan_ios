import SwiftUI

struct MeetingDetailView: View {
    @EnvironmentObject var auth: AuthStore
    let meetingId: String

    @State private var meeting: Meeting?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // action state
    @State private var showCancelConfirm = false
    @State private var showRescheduleSheet = false
    @State private var showProposalSheet = false
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let m = meeting {
                    header(m)
                    if let url = m.meetingUrl, let u = URL(string: url) {
                        Link(destination: u) {
                            Label("会議に参加", systemImage: "video.fill")
                                .frame(maxWidth: .infinity).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let notes = m.notes, !notes.isEmpty {
                        Card {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("メモ").font(.caption).foregroundStyle(.secondary)
                                Text(notes)
                            }
                        }
                    }
                    if let proposed = m.proposedStartAt, let d = JSTDate.parseTimestamp(proposed), m.rescheduleState == .proposed {
                        proposalCard(start: d, note: m.rescheduleNote)
                    }
                    actionsSection(m)
                }
            }
            .padding(20)
        }
        .background(Theme.groupedBackground.ignoresSafeArea())
        .navigationTitle("面談詳細")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .overlay { if isLoading && meeting == nil { ProgressView() } }
        .errorAlert($errorMessage)
        .confirmationDialog("この面談をキャンセルしますか？", isPresented: $showCancelConfirm, titleVisibility: .visible) {
            Button("キャンセルする", role: .destructive) { Task { await cancel() } }
        }
        .sheet(isPresented: $showRescheduleSheet) {
            NoteSheet(title: "リスケ希望を送る") { note in Task { await requestReschedule(note: note) } }
        }
        .sheet(isPresented: $showProposalSheet) {
            ProposalSheet { start, duration, note in
                Task { await propose(start: start, duration: duration, note: note) }
            }
        }
    }

    private func header(_ m: Meeting) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(m.title).font(.headline)
                if let start = JSTDate.parseTimestamp(m.scheduledStartAt),
                   let end = JSTDate.parseTimestamp(m.scheduledEndAt) {
                    Text("\(JSTDate.displayLong.string(from: start)) \(JSTDate.time.string(from: start))〜\(JSTDate.time.string(from: end))")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    Label(m.displayStatus.label, systemImage: "circle.fill")
                        .font(.caption)
                    if let t = m.teacher?.displayName {
                        Label(t, systemImage: "person.fill").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func proposalCard(start: Date, note: String?) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("講師から新しい日時が提案されています")
                    .font(.subheadline).bold().foregroundStyle(.orange)
                Text(JSTDate.displayLong.string(from: start) + " " + JSTDate.time.string(from: start))
                    .font(.subheadline)
                if let note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button {
                        Task { await acceptProposal() }
                    } label: { Text("受け入れる").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy)
                    Button {
                        Task { await rejectProposal() }
                    } label: { Text("拒否する").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                    .disabled(busy)
                }
            }
        }
    }

    private func actionsSection(_ m: Meeting) -> some View {
        VStack(spacing: 10) {
            if m.status == .scheduled && !m.isPast {
                Button {
                    showRescheduleSheet = true
                } label: { Label("リスケを希望する", systemImage: "arrow.triangle.2.circlepath").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button {
                    showProposalSheet = true
                } label: { Label("別日時を提案する", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
                Button(role: .destructive) {
                    showCancelConfirm = true
                } label: { Label("この面談をキャンセル", systemImage: "xmark.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do { meeting = try await MeetingsRepository(api: auth.api).detail(meetingId) }
        catch let e as APIError { errorMessage = e.errorDescription }
        catch { errorMessage = "読み込みに失敗しました" }
    }

    private func cancel() async {
        busy = true; defer { busy = false }
        do { try await MeetingsRepository(api: auth.api).cancel(meetingId, note: nil); await load() }
        catch let e as APIError { errorMessage = e.errorDescription }
        catch { errorMessage = "キャンセルに失敗しました" }
    }

    private func requestReschedule(note: String?) async {
        busy = true; defer { busy = false }
        do { try await MeetingsRepository(api: auth.api).requestReschedule(meetingId, note: note); await load() }
        catch let e as APIError { errorMessage = e.errorDescription }
        catch { errorMessage = "送信に失敗しました" }
    }

    private func propose(start: Date, duration: Int, note: String?) async {
        busy = true; defer { busy = false }
        do { try await MeetingsRepository(api: auth.api).proposeReschedule(meetingId, start: start, durationMinutes: duration, note: note); await load() }
        catch let e as APIError { errorMessage = e.errorDescription }
        catch { errorMessage = "提案に失敗しました" }
    }

    private func acceptProposal() async {
        busy = true; defer { busy = false }
        do { try await MeetingsRepository(api: auth.api).acceptProposal(meetingId); await load() }
        catch let e as APIError { errorMessage = e.errorDescription }
        catch { errorMessage = "処理に失敗しました" }
    }

    private func rejectProposal() async {
        busy = true; defer { busy = false }
        do { try await MeetingsRepository(api: auth.api).rejectProposal(meetingId, note: nil); await load() }
        catch let e as APIError { errorMessage = e.errorDescription }
        catch { errorMessage = "処理に失敗しました" }
    }
}

// MARK: - Sheets

private struct NoteSheet: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let onSubmit: (String?) -> Void

    @State private var note: String = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("メッセージ (任意)") {
                    TextField("メッセージ", text: $note, axis: .vertical).lineLimit(2...6)
                }
                Section {
                    Button {
                        onSubmit(note.isEmpty ? nil : note)
                        dismiss()
                    } label: { Text("送信").bold().frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
            }
        }
    }
}

private struct ProposalSheet: View {
    @Environment(\.dismiss) var dismiss
    let onSubmit: (Date, Int, String?) -> Void

    @State private var start: Date = Date().addingTimeInterval(60 * 60 * 24)
    @State private var duration: Int = 60
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("提案する日時") {
                    DatePicker("開始", selection: $start)
                        .environment(\.locale, Locale(identifier: "ja_JP"))
                    Stepper("時間: \(duration) 分", value: $duration, in: 15...240, step: 15)
                }
                Section("メモ (任意)") {
                    TextField("メモ", text: $note, axis: .vertical).lineLimit(2...5)
                }
                Section {
                    Button {
                        onSubmit(start, duration, note.isEmpty ? nil : note)
                        dismiss()
                    } label: { Text("提案する").bold().frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                }
            }
            .navigationTitle("別日時を提案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
            }
        }
    }
}
