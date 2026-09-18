import SwiftUI

/// リスケフローの "現在の状況 × 自分" を 5 相に切り分ける。UI 側はこの phase を
/// 見て「あなたが次に何をすべきか」を出し分ける。Web 版 MeetingDetailView.tsx
/// の computePhase と同じ規約。
private enum ReschedulePhase {
    case none                 // 予定通り、誰も動いていない
    case requestedByMe        // 自分が「変えたい」希望を送った (相手待ち)
    case requestedByOther     // 相手が希望を送ってきた (自分が具体提案する番)
    case proposedByMe         // 自分が具体日時を提案した (相手待ち)
    case proposedByOther      // 相手が具体日時を提案してきた (承認/対案/見送る)
}

struct MeetingDetailView: View {
    @EnvironmentObject var auth: AuthStore
    let meetingId: String

    @State private var meeting: Meeting?
    @State private var isLoading = false
    @State private var errorMessage: String?

    // action state
    @State private var showCancelConfirm = false
    @State private var showRequestSheet = false
    @State private var showProposalSheet = false
    @State private var busy = false

    private var currentUserId: String? { auth.currentUser?.id }

    private var phase: ReschedulePhase {
        guard let m = meeting else { return .none }
        let iAmActor = m.rescheduleActor != nil && m.rescheduleActor == currentUserId
        switch m.rescheduleState {
        case .requested: return iAmActor ? .requestedByMe : .requestedByOther
        case .proposed: return iAmActor ? .proposedByMe : .proposedByOther
        case .none: return .none
        }
    }

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

                    // phase != .none の時だけ状況パネル (混在ボタン回避)
                    if phase != .none && m.status == .scheduled && !m.isPast {
                        reschedulePanel(m)
                    }

                    // NONE 時だけ通常アクションバー
                    if phase == .none && m.status == .scheduled && !m.isPast {
                        VStack(spacing: 10) {
                            Button {
                                showRequestSheet = true
                            } label: {
                                Label("リスケを希望する", systemImage: "arrow.triangle.2.circlepath")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
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
        .sheet(isPresented: $showRequestSheet) {
            NoteSheet(title: "リスケ希望を送る",
                      description: "相手に「日程を変えたい」ことを伝えます。新しい日時は相手が提案します。",
                      requireNote: true) { note in
                Task { await requestReschedule(note: note) }
            }
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

    /// リスケ状況パネル。phase に応じて「今の状況」+「あなたが次にすべきこと」+
    /// アクションボタンをまとめて出す。混在ボタン回避のため他の通常アクション
    /// (リスケ希望を送る) は phase == .none のときだけ外側に出す。
    @ViewBuilder
    private func reschedulePanel(_ m: Meeting) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(phaseTitle).font(.subheadline).bold()
                        Text(phaseHint).font(.caption).foregroundStyle(.secondary)
                    }
                }

                // 提案されている日時 (proposed 時のみ)
                if let proposed = m.proposedStartAt,
                   let d = JSTDate.parseTimestamp(proposed),
                   (phase == .proposedByMe || phase == .proposedByOther) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("提案されている日時").font(.caption).foregroundStyle(.secondary)
                        Text(JSTDate.displayLong.string(from: d) + " " + JSTDate.time.string(from: d))
                            .font(.subheadline)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemBackground)))
                }

                if let note = m.rescheduleNote, !note.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("相手のメモ").font(.caption).foregroundStyle(.secondary)
                        Text(note).font(.subheadline)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemBackground)))
                }

                phaseActions
            }
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .requestedByMe: return "リスケ希望を送信しました"
        case .requestedByOther: return "相手からリスケ希望が届いています"
        case .proposedByMe: return "新しい日程を提案しました"
        case .proposedByOther: return "新しい日程が提案されています"
        case .none: return ""
        }
    }

    private var phaseHint: String {
        switch phase {
        case .requestedByMe, .proposedByMe: return "相手の返答を待っています。"
        case .requestedByOther: return "あなたのすべきこと: 新しい日程を提案してください。"
        case .proposedByOther: return "あなたのすべきこと: 承認・別日を提案・見送る のいずれかを選んでください。"
        case .none: return ""
        }
    }

    @ViewBuilder
    private var phaseActions: some View {
        switch phase {
        case .requestedByOther:
            VStack(spacing: 8) {
                Button {
                    showProposalSheet = true
                } label: {
                    Label("新しい日程を提案する", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                Button {
                    Task { await withdraw() }
                } label: {
                    Label("希望を取り下げる", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }
        case .proposedByOther:
            VStack(spacing: 8) {
                Button {
                    Task { await acceptProposal() }
                } label: {
                    Label("この日時で承認", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy)
                Button {
                    showProposalSheet = true
                } label: {
                    Label("別の日を提案", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(busy)
                Button(role: .destructive) {
                    Task { await rejectProposal() }
                } label: {
                    Label("見送る (相手に返す)", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }
        case .requestedByMe, .proposedByMe:
            Button {
                Task { await withdraw() }
            } label: {
                Label("取り下げる", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(busy)
        case .none:
            EmptyView()
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

    private func withdraw() async {
        busy = true; defer { busy = false }
        do { try await MeetingsRepository(api: auth.api).withdrawReschedule(meetingId); await load() }
        catch let e as APIError { errorMessage = e.errorDescription }
        catch { errorMessage = "取り下げに失敗しました" }
    }
}

// MARK: - Sheets

private struct NoteSheet: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let description: String?
    /// true のときはメモが空だと送信不可 (リスケ希望など理由必須のケース向け)
    let requireNote: Bool
    let onSubmit: (String?) -> Void

    @State private var note: String = ""

    init(
        title: String,
        description: String? = nil,
        requireNote: Bool = false,
        onSubmit: @escaping (String?) -> Void,
    ) {
        self.title = title
        self.description = description
        self.requireNote = requireNote
        self.onSubmit = onSubmit
    }

    var body: some View {
        NavigationStack {
            Form {
                if let description {
                    Section {
                        Text(description).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section(requireNote ? "理由" : "メッセージ (任意)") {
                    TextField(requireNote ? "例: 塾があるので別の日にしたい" : "メッセージ",
                              text: $note, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Button {
                        onSubmit(note.isEmpty ? nil : note)
                        dismiss()
                    } label: { Text("送信").bold().frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent)
                    .disabled(requireNote && note.trimmingCharacters(in: .whitespaces).isEmpty)
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
            .navigationTitle("日程を提案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("キャンセル") { dismiss() } }
            }
        }
    }
}
