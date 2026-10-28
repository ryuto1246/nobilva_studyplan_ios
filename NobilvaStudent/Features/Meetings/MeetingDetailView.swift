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

    var isMine: Bool { self == .requestedByMe || self == .proposedByMe }
}

struct MeetingDetailView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var toast: ToastCenter
    let meetingId: String

    @State private var meeting: Meeting?
    @State private var isLoading = true
    @State private var errorMessage: String?

    @State private var showCancelConfirm = false
    @State private var showAcceptConfirm = false
    @State private var showRequestSheet = false
    @State private var showProposalSheet = false
    @State private var showRejectSheet = false
    @State private var busy = false

    private var phase: ReschedulePhase {
        guard let m = meeting else { return .none }
        let iAmActor = m.rescheduleActor != nil && m.rescheduleActor == auth.currentUser?.id
        switch m.rescheduleState {
        case .requested: return iAmActor ? .requestedByMe : .requestedByOther
        case .proposed: return iAmActor ? .proposedByMe : .proposedByOther
        case .none: return .none
        }
    }

    private var repo: MeetingsRepository { MeetingsRepository(api: auth.api) }

    var body: some View {
        Group {
            if let m = meeting {
                content(m)
            } else if isLoading {
                LoadingStateView()
            } else {
                RetryStateView { await load() }
            }
        }
        .background(Theme.groupedBackground.ignoresSafeArea())
        .navigationTitle("面談")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
        .errorAlert($errorMessage)
        .sheet(isPresented: $showRequestSheet) {
            NoteSheet(title: "日程の変更を希望",
                      description: "先生に「日程を変えたい」ことを伝えます。新しい日時は先生が提案します。",
                      placeholder: "例: 塾があるので別の日にしたいです",
                      requireNote: true, submitLabel: "送信") { note in
                try await repo.requestReschedule(meetingId, note: note)
                toast.show("日程の変更を希望しました")
                await load()
            }
        }
        .sheet(isPresented: $showRejectSheet) {
            NoteSheet(title: "提案を見送る",
                      description: "提案された日時は都合が合わないことを先生に伝えます。",
                      placeholder: "例: その日は部活があります",
                      requireNote: false, submitLabel: "見送る") { note in
                try await repo.rejectProposal(meetingId, note: note)
                toast.show("提案を見送りました")
                await load()
            }
        }
        .sheet(isPresented: $showProposalSheet) {
            ProposalSheet { start, duration, note in
                try await repo.proposeReschedule(meetingId, start: start, durationMinutes: duration, note: note)
                toast.show("新しい日時を提案しました")
                await load()
            }
        }
    }

    private func content(_ m: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(m)
                if let url = m.joinURL {
                    Link(destination: url) {
                        Label("面談に参加", systemImage: "video.fill")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 34)
                    }
                    .buttonStyle(.borderedProminent)
                }
                if let notes = m.notes, !notes.isEmpty {
                    infoBox(title: "メモ", body: notes)
                }
                if m.isUpcoming {
                    if phase == .none {
                        VStack(spacing: 4) {
                            SecondaryButton("日程の変更を希望する", systemImage: "arrow.triangle.2.circlepath") {
                                showRequestSheet = true
                            }
                            Button("面談をキャンセル", role: .destructive) { showCancelConfirm = true }
                                .frame(minHeight: 44)
                                .confirmationDialog("この面談をキャンセルしますか？", isPresented: $showCancelConfirm, titleVisibility: .visible) {
                                    Button("面談をキャンセル", role: .destructive) {
                                        Task { await perform("面談をキャンセルしました") { try await repo.cancel(meetingId, note: nil) } }
                                    }
                                } message: {
                                    Text("先生に通知されます。日程を変えたいだけなら「日程の変更を希望する」を使ってください。")
                                }
                        }
                        .disabled(busy)
                    } else {
                        reschedulePanel(m)
                    }
                }
            }
            .padding(16)
        }
    }

    private func header(_ m: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(m.title).font(.title3.bold())
                Spacer()
                StatusBadge(text: m.displayStatus.label,
                            tint: m.displayStatus.tint == "orange" ? .orange : .secondary)
            }
            if let start = m.startDate, let end = JSTDate.parseTimestamp(m.scheduledEndAt) {
                Text("\(JSTDate.displayMonthDay.string(from: start)) \(JSTDate.time.string(from: start))〜\(JSTDate.time.string(from: end))")
                    .font(.body)
            }
            HStack(spacing: 12) {
                if let c = m.countdownLabel { Text(c).foregroundStyle(Theme.accent) }
                if let t = m.teacher?.displayName { Label(t, systemImage: "person.fill").foregroundStyle(.secondary) }
            }
            .font(.subheadline)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoBox(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(body).font(.subheadline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func reschedulePanel(_ m: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label(phaseTitle, systemImage: phase.isMine ? "hourglass" : "exclamationmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(phase.isMine ? Color.secondary : Color.orange)
                Text(phaseHint).font(.subheadline).foregroundStyle(.secondary)
            }
            if let proposed = m.proposedStartAt, let d = JSTDate.parseTimestamp(proposed),
               phase == .proposedByMe || phase == .proposedByOther {
                infoBox(title: "提案されている日時",
                        body: JSTDate.displayMonthDay.string(from: d) + " " + JSTDate.time.string(from: d))
            }
            if let note = m.rescheduleNote, !note.isEmpty {
                infoBox(title: phase.isMine ? "あなたが送ったメモ" : "先生からのメモ", body: note)
            }
            phaseActions
        }
        .padding(16)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
    }

    private var phaseTitle: String {
        switch phase {
        case .requestedByMe: return "日程の変更を希望しています"
        case .requestedByOther: return "先生が日程の変更を希望しています"
        case .proposedByMe: return "新しい日時を提案しました"
        case .proposedByOther: return "先生から新しい日時の提案があります"
        case .none: return ""
        }
    }

    private var phaseHint: String {
        switch phase {
        case .requestedByMe, .proposedByMe: return "先生の返事を待っています。"
        case .requestedByOther: return "都合のよい日時を提案してください。"
        case .proposedByOther: return "確定するか、別の日時を提案するか、見送るかを選んでください。"
        case .none: return ""
        }
    }

    @ViewBuilder
    private var phaseActions: some View {
        VStack(spacing: 8) {
            switch phase {
            case .requestedByOther:
                // 相手の希望は取り下げられない (サーバが拒否する) ので、提案だけ。
                PrimaryButton("新しい日時を提案する", systemImage: "calendar.badge.plus") { showProposalSheet = true }
            case .proposedByOther:
                PrimaryButton("この日時で確定", systemImage: "checkmark") { showAcceptConfirm = true }
                    .confirmationDialog("提案された日時で確定しますか？", isPresented: $showAcceptConfirm, titleVisibility: .visible) {
                        Button("この日時で確定") {
                            Task { await perform("面談の日時を確定しました") { try await repo.acceptProposal(meetingId) } }
                        }
                    }
                SecondaryButton("別の日時を提案", systemImage: "calendar.badge.plus") { showProposalSheet = true }
                Button("見送る", role: .destructive) { showRejectSheet = true }
                    .frame(minHeight: 44)
            case .requestedByMe, .proposedByMe:
                SecondaryButton("取り下げる", systemImage: "arrow.uturn.backward", isLoading: busy) {
                    Task { await perform("取り下げました") { try await repo.withdrawReschedule(meetingId) } }
                }
            case .none:
                EmptyView()
            }
        }
        .disabled(busy)
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            meeting = try await repo.detail(meetingId)
        } catch {
            // 表示中のデータがあるときは、更新失敗のたびにアラートを出さない。
            if meeting == nil, (error as? APIError)?.isCancelled != true {
                errorMessage = (error as? APIError)?.errorDescription ?? "読み込めませんでした"
            }
        }
    }

    private func perform(_ doneMessage: String, _ op: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await op()
            toast.show(doneMessage)
            await load()
            NotificationCenter.default.post(name: .studyDataDidChange, object: nil)
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "処理できませんでした"
        }
    }
}

// MARK: - Sheets

/// メモ付きで何かを送るシート。送信が成功してから閉じる。
private struct NoteSheet: View {
    @Environment(\.dismiss) var dismiss
    let title: String
    let description: String?
    let placeholder: String
    let requireNote: Bool
    let submitLabel: String
    let onSubmit: (String?) async throws -> Void

    @State private var note = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private var trimmed: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                if let description {
                    Section { Text(description).font(.subheadline).foregroundStyle(.secondary) }
                }
                Section(requireNote ? "理由" : "メッセージ (任意)") {
                    TextField(placeholder, text: $note, axis: .vertical).lineLimit(2...6)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending { ProgressView() } else {
                        Button(submitLabel) { Task { await submit() } }
                            .disabled(requireNote && trimmed.isEmpty)
                    }
                }
            }
            .interactiveDismissDisabled(isSending || !trimmed.isEmpty)
            .errorAlert($errorMessage)
        }
    }

    private func submit() async {
        isSending = true
        defer { isSending = false }
        do {
            try await onSubmit(trimmed.isEmpty ? nil : trimmed)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "送信できませんでした"
        }
    }
}

private struct ProposalSheet: View {
    @Environment(\.dismiss) var dismiss
    let onSubmit: (Date, Int, String?) async throws -> Void

    @State private var start: Date = ProposalSheet.defaultStart()
    @State private var duration: Int = 60
    @State private var note = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    /// 明日の同じ時刻を 15 分単位に丸めた値。
    private static func defaultStart() -> Date {
        let tomorrow = Date().addingTimeInterval(60 * 60 * 24)
        let interval = 15.0 * 60
        return Date(timeIntervalSinceReferenceDate: (tomorrow.timeIntervalSinceReferenceDate / interval).rounded(.up) * interval)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("提案する日時") {
                    DatePicker("開始", selection: $start, in: Date()...)
                        .environment(\.timeZone, JSTDate.timeZone)
                        .environment(\.calendar, JSTDate.calendar)
                    Picker("長さ", selection: $duration) {
                        ForEach([15, 30, 45, 60, 90, 120], id: \.self) { m in Text(formatMinutes(m)).tag(m) }
                    }
                }
                Section("メモ (任意)") {
                    TextField("メモ", text: $note, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle("日時を提案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending { ProgressView() } else { Button("提案") { Task { await submit() } } }
                }
            }
            .interactiveDismissDisabled(isSending)
            .errorAlert($errorMessage)
        }
    }

    private func submit() async {
        isSending = true
        defer { isSending = false }
        let memo = note.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await onSubmit(start, duration, memo.isEmpty ? nil : memo)
            dismiss()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? "提案できませんでした"
        }
    }
}
