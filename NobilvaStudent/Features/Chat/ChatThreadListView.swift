import SwiftUI

/// チャットタブ。相手は担当の先生 2〜3 人程度なので、一覧というより「先生ごとのカード」。
/// 各カードに最後のメッセージ (吹き出し)・時刻・未読数と、その先生との次の面談を出す。
struct ChatThreadListView: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase

    @State private var contacts: [ChatContact] = []
    @State private var meetings: [Meeting] = []
    @State private var isLoading = true
    @State private var loadFailed = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && contacts.isEmpty {
                    LoadingStateView()
                } else if loadFailed && contacts.isEmpty {
                    RetryStateView { await load() }
                } else if contacts.isEmpty {
                    ContentUnavailableView("チャットできる先生はまだいません", systemImage: "bubble.left.and.bubble.right",
                                           description: Text("担当の先生が決まると、ここからチャットできます。"))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(contacts) { c in
                                ChatContactCard(contact: c, nextMeeting: nextMeeting(with: c))
                                    .tourTarget(c.id == contacts.first?.id ? .chatFirstContact : nil)
                            }
                        }
                        .padding(16)
                    }
                    .background(Theme.groupedBackground.ignoresSafeArea())
                }
            }
            .navigationTitle("チャット")
            .task {
                if contacts.isEmpty {
                    contacts = ChatContact.merge(threads: ChatRepository.cachedThreads() ?? [],
                                                 partners: ChatRepository.cachedPartners() ?? [])
                }
                if meetings.isEmpty { meetings = MeetingsRepository.cachedList(includePast: false) ?? [] }
                await load()
            }
            .refreshable { await load() }
            .onChange(of: scenePhase) { _, p in if p == .active { Task { await load() } } }
        }
        // push 先の画面でも計測バーを出すため、NavigationStack の外側に付ける。
        .timerAccessory()
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let repo = ChatRepository(api: auth.api)
            async let t = repo.threads()
            async let p = repo.partners()
            contacts = ChatContact.merge(threads: try await t, partners: try await p)
            loadFailed = false
            // 面談はカードの補足なので、取れなくても一覧は出す。
            if let m = try? await MeetingsRepository(api: auth.api).list() { meetings = m }
        } catch {
            loadFailed = true
        }
    }
}

/// その先生との、これからの面談のうちいちばん近いもの。
extension ChatThreadListView {
    fileprivate func nextMeeting(with c: ChatContact) -> Meeting? {
        meetings
            .filter { m in
                guard m.isUpcoming, let id = c.teacherId else { return false }
                return m.teacherId == id || m.teacher?.id == id
            }
            .min { $0.scheduledStartAt < $1.scheduledStartAt }
    }
}

/// 一覧の 1 行 = 先生 1 人。スレッドが未作成の先生も同じ行で出し、開いたときに作る。
struct ChatContact: Identifiable, Hashable {
    let id: String
    let teacherId: String?
    let threadId: String?
    let name: String
    let lastBody: String?
    let lastAt: Date?
    let unread: Int

    static func merge(threads: [ChatThread], partners: [ChatPartner]) -> [ChatContact] {
        var result = threads.map { t in
            ChatContact(
                id: t.teacherId ?? t.id, teacherId: t.teacherId, threadId: t.id,
                name: t.teacherName ?? "先生", lastBody: t.lastMessageBody,
                lastAt: t.lastMessageAt.flatMap(JSTDate.parseTimestamp), unread: t.unreadCount ?? 0
            )
        }
        let existing = Set(result.compactMap(\.teacherId))
        result += partners.filter { !existing.contains($0.teacherId) }.map { p in
            ChatContact(id: p.teacherId, teacherId: p.teacherId, threadId: nil, name: p.displayName,
                        lastBody: nil, lastAt: nil, unread: 0)
        }
        // 未読がある人 → 最近やり取りした人 → まだ話していない人
        return result.sorted {
            if ($0.unread > 0) != ($1.unread > 0) { return $0.unread > 0 }
            return ($0.lastAt ?? .distantPast) > ($1.lastAt ?? .distantPast)
        }
    }
}

/// 先生 1 人分のカード。上半分 (名前・最後のメッセージ) をタップで会話へ、
/// 下の面談の行をタップで面談詳細へ。
private struct ChatContactCard: View {
    let contact: ChatContact
    let nextMeeting: Meeting?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink {
                ChatRoomView(threadId: contact.threadId, teacherId: contact.teacherId, title: contact.name)
            } label: {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    lastMessage
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(contact.unread > 0 ? "未読 \(contact.unread)件" : "")
            .accessibilityHint("会話を開きます")

            if let m = nextMeeting {
                Divider().padding(.leading, 16)
                NavigationLink {
                    MeetingDetailView(meetingId: m.id)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "calendar")
                            .foregroundStyle(m.isToday ? Theme.accent : .secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.isToday ? "今日の面談" : "次の面談")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text([m.scheduleLabel, m.countdownLabel].compactMap { $0 }.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(Color.primary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if contact.unread > 0 {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ChatAvatar(name: contact.name, size: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.title3.bold())
                Text("担当の先生")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if let at = contact.lastAt {
                    Text(JSTDate.listTimestamp(at))
                        .font(.subheadline)
                        .foregroundStyle(contact.unread > 0 ? Theme.accent : .secondary)
                }
                if contact.unread > 0 {
                    Text("\(contact.unread)")
                        .font(.subheadline.bold().monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(minWidth: 26, minHeight: 26)
                        .background(Theme.accent, in: Capsule())
                }
            }
        }
    }

    /// 最後のメッセージを相手の吹き出しの形で。まだ無ければ話しかけるきっかけを出す。
    @ViewBuilder
    private var lastMessage: some View {
        if let body = contact.lastBody, !body.isEmpty {
            Text(ChatTaskCardParser.preview(body))
                .font(.body)
                .foregroundStyle(contact.unread > 0 ? Color.primary : Color.secondary)
                .fontWeight(contact.unread > 0 ? .semibold : .regular)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.groupedBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            Label("わからないことを気軽に聞いてみましょう", systemImage: "bubble.left")
                .font(.subheadline)
                .foregroundStyle(Theme.accent)
        }
    }
}
