import SwiftUI
import PhotosUI
import UIKit

/// 1 人の先生との会話。
/// - スレッドがまだ無い先生は、最初の読み込み時に作る
/// - 会話中はタブバーを隠す (メッセージ系アプリの標準)
/// - 日付の区切り・お知らせ (管理者メッセージ) の区別・長押しコピー・画像の拡大
struct ChatRoomView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var chatUnread: ChatUnreadStore
    @Environment(\.scenePhase) private var scenePhase

    let teacherId: String?
    let title: String
    @State private var threadId: String?

    @State private var messages: [ChatMessage] = []
    @State private var pending: [PendingMessage] = []
    @State private var draft = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var viewingImage: ViewingImage?
    /// 最後のメッセージが画面内にあるか (新着で自動スクロールしてよいか)。
    @State private var isAtBottom = true
    @FocusState private var isInputFocused: Bool

    private static let maxLength = 2000

    init(threadId: String?, teacherId: String?, title: String) {
        self.teacherId = teacherId
        self.title = title
        _threadId = State(initialValue: threadId)
    }

    /// 送信中・失敗した自分のメッセージ (サーバに届くまでの仮表示)。
    struct PendingMessage: Identifiable, Equatable {
        let id = UUID()
        let body: String?
        let imageData: Data?
        var failed = false
    }

    var body: some View {
        messageScroll
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            .task {
                await load(initial: true)
                // 画面を開いている間だけ 15 秒ごとに取り直す (.task なので閉じると自動で止まる)。
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 15_000_000_000)
                    if Task.isCancelled { break }
                    await load()
                }
            }
            .onChange(of: scenePhase) { _, p in if p == .active { Task { await load() } } }
            .onDisappear { Task { await chatUnread.refresh() } }
            .errorAlert($errorMessage)
            .fullScreenCover(item: $viewingImage) { v in
                ChatImageViewer(url: v.url)
            }
    }

    // MARK: - Message list

    private var messageScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if isLoading && messages.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if messages.isEmpty && pending.isEmpty {
                        Text("まだメッセージはありません。\nわからないことを気軽に聞いてみましょう。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 60)
                    }
                    ForEach(dayGroups, id: \.day) { group in
                        DaySeparator(text: group.label)
                        ForEach(group.messages) { m in
                            messageView(m)
                        }
                    }
                    ForEach(pending) { p in
                        PendingBubble(message: p,
                                      retry: { Task { await resend(p) } },
                                      discard: { pending.removeAll { $0.id == p.id } })
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear { isAtBottom = true }
                        .onDisappear { isAtBottom = false }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.groupedBackground)
            .onChange(of: messages.last?.id) { _, _ in
                if isAtBottom { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .onChange(of: pending.count) { old, new in
                if new > old { withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            .onChange(of: isInputFocused) { _, focused in
                guard focused else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }

    @ViewBuilder
    private func messageView(_ m: ChatMessage) -> some View {
        if m.isAdminMessage == true {
            NoticeMessage(message: m)
        } else {
            MessageBubble(message: m, isMine: m.senderId == auth.currentUser?.id) { url in
                viewingImage = ViewingImage(url: url)
            }
        }
    }

    private struct DayGroup { let day: String; let label: String; let messages: [ChatMessage] }

    /// JST の日付ごとにまとめる。
    private var dayGroups: [DayGroup] {
        var groups: [DayGroup] = []
        for m in messages {
            let date = JSTDate.parseTimestamp(m.createdAt) ?? Date()
            let day = JSTDate.iso.string(from: date)
            if let last = groups.last, last.day == day {
                groups[groups.count - 1] = DayGroup(day: day, label: last.label, messages: last.messages + [m])
            } else {
                groups.append(DayGroup(day: day, label: JSTDate.dayHeader(date), messages: [m]))
            }
        }
        return groups
    }

    // MARK: - Composer

    private var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmedDraft.isEmpty && trimmedDraft.count <= Self.maxLength }

    private var composer: some View {
        VStack(spacing: 4) {
            if trimmedDraft.count > Self.maxLength - 200 {
                Text("\(trimmedDraft.count) / \(Self.maxLength)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(trimmedDraft.count > Self.maxLength ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $photoPickerItem, matching: .images) {
                    Image(systemName: "photo")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("写真を送る")
                .onChange(of: photoPickerItem) { _, item in
                    guard let item else { return }
                    Task { await handlePickedImage(item) }
                }

                HStack(alignment: .bottom, spacing: 4) {
                    TextField("メッセージ", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($isInputFocused)
                        .padding(.leading, 14)
                        .padding(.vertical, 10)
                    Button {
                        Task { await send() }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(canSend ? Theme.accent : Color.gray.opacity(0.4))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSend)
                    .accessibilityLabel("送信")
                }
                .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Theme.separator.opacity(0.4), lineWidth: 0.5))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Loading

    private func repo() -> ChatRepository { ChatRepository(api: auth.api) }

    private func load(initial: Bool = false) async {
        defer { isLoading = false }
        do {
            if threadId == nil {
                guard let teacherId else { return }
                threadId = try await repo().createOrGetThread(teacherId: teacherId).threadId
            }
            guard let threadId else { return }
            let fetched = try await repo().messages(threadId: threadId)
            let hadNew = fetched.last?.id != messages.last?.id
            // 開いている間に相手から届いたら、軽く知らせる (初回読み込みと自分の送信は除く)。
            if !initial, hadNew, let last = fetched.last, last.senderId != auth.currentUser?.id {
                Haptics.tap()
            }
            messages = fetched
            if initial || hadNew {
                // 開いている間に届いたものも既読にする。
                try? await repo().markRead(threadId: threadId)
            }
        } catch {
            if initial, (error as? APIError)?.isCancelled != true {
                errorMessage = (error as? APIError)?.errorDescription ?? "メッセージを読み込めませんでした"
            }
        }
    }

    // MARK: - Sending

    private func send() async {
        let text = trimmedDraft
        guard canSend else { return }
        draft = ""
        Haptics.tap()
        let p = PendingMessage(body: text, imageData: nil)
        pending.append(p)
        await deliver(p)
    }

    private func resend(_ p: PendingMessage) async {
        guard let idx = pending.firstIndex(of: p) else { return }
        pending[idx].failed = false
        await deliver(pending[idx])
    }

    /// 送信して、成功したら一覧を取り直して仮表示を消す。失敗したら「再送」を出す (本文は残す)。
    private func deliver(_ p: PendingMessage) async {
        do {
            // スレッドをまだ作れていなければ、ここで作ってから送る (再送でも同じ)。
            if threadId == nil, let teacherId {
                threadId = try await repo().createOrGetThread(teacherId: teacherId).threadId
            }
            guard let threadId else { throw APIError.invalidResponse }
            if let data = p.imageData {
                _ = try await repo().sendImage(threadId: threadId, imageData: data, contentType: "image/jpeg", caption: nil)
            } else if let body = p.body {
                _ = try await repo().send(threadId: threadId, body: body)
            }
            messages = (try? await repo().messages(threadId: threadId)) ?? messages
            pending.removeAll { $0.id == p.id }
        } catch {
            if let idx = pending.firstIndex(where: { $0.id == p.id }) { pending[idx].failed = true }
            Haptics.error()
        }
    }

    private func handlePickedImage(_ item: PhotosPickerItem) async {
        defer { photoPickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data),
              let jpeg = Self.compress(image, longEdge: 1600, quality: 0.7) else {
            errorMessage = "この画像は送れませんでした。別の写真を選んでください。"
            return
        }
        let p = PendingMessage(body: nil, imageData: jpeg)
        pending.append(p)
        await deliver(p)
    }

    private static func compress(_ image: UIImage, longEdge: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let scale = min(1.0, longEdge / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

/// 全画面で見ている画像。URL そのものに Identifiable を後付けしないための包み。
private struct ViewingImage: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

// MARK: - Parts

private struct DaySeparator: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(Theme.secondaryBackground, in: Capsule())
            .padding(.vertical, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 管理者 (運営) からのお知らせ。先生の発言と区別するため吹き出しにせず中央に置く。
private struct NoticeMessage: View {
    let message: ChatMessage

    var body: some View {
        VStack(spacing: 4) {
            Label("お知らせ", systemImage: "megaphone.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let body = message.body, !body.isEmpty {
                Text(body)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
            }
            if let ts = JSTDate.parseTimestamp(message.createdAt) {
                Text(JSTDate.time.string(from: ts))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: 320)
        .background(Theme.secondaryBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.separator.opacity(0.4), style: StrokeStyle(lineWidth: 0.5, dash: [3])))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct MessageBubble: View {
    let message: ChatMessage
    let isMine: Bool
    let onTapImage: (URL) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMine { Spacer(minLength: 48); timeText }
            content
            if !isMine { timeText; Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private var timeText: some View {
        if let ts = JSTDate.parseTimestamp(message.createdAt) {
            Text(JSTDate.time.string(from: ts))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var content: some View {
        let parsed = message.body.flatMap { ChatTaskCardParser.parse($0) }
        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            if let s = message.imageUrl, let url = URL(string: s) {
                ChatImageThumbnail(url: url) { onTapImage(url) }
            }
            if let parsed {
                VStack(alignment: .leading, spacing: 6) {
                    TaskCardChip(card: parsed.card, isMine: isMine)
                    if !parsed.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(parsed.message)
                    }
                }
                .bubble(isMine: isMine)
                .copyable(parsed.message)
            } else if let body = message.body, !body.isEmpty {
                Text(body)
                    .bubble(isMine: isMine)
                    .copyable(body)
            }
        }
    }
}

private struct PendingBubble: View {
    let message: ChatRoomView.PendingMessage
    let retry: () -> Void
    let discard: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            Spacer(minLength: 48)
            if message.failed {
                Menu {
                    Button("もう一度送る", action: retry)
                    Button("削除", role: .destructive, action: discard)
                } label: {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("送信できませんでした")
            } else {
                ProgressView().controlSize(.small)
            }
            Group {
                if let data = message.imageData, let img = UIImage(data: data) {
                    Image(uiImage: img)
                        .resizable().scaledToFit()
                        .frame(maxWidth: 200, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if let body = message.body {
                    Text(body).bubble(isMine: true)
                }
            }
            .opacity(message.failed ? 1 : 0.6)
        }
    }
}

private struct ChatImageThumbnail: View {
    let url: URL
    let onTap: () -> Void

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let img):
                img.resizable().scaledToFit()
            case .failure:
                Label("画像を表示できません", systemImage: "photo")
                    .font(.footnote).foregroundStyle(.secondary)
                    .frame(width: 180, height: 120)
                    .background(Theme.secondaryBackground)
            default:
                Theme.secondaryBackground.frame(width: 180, height: 140).overlay(ProgressView())
            }
        }
        .frame(maxWidth: 240, maxHeight: 320)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("画像。タップで拡大")
    }
}

/// 画像の全画面表示。ピンチで拡大、共有シートから保存できる。
private struct ChatImageViewer: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var image: UIImage?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image {
                    Image(uiImage: image)
                        .resizable().scaledToFit()
                        .scaleEffect(scale)
                        .gesture(MagnifyGesture()
                            .onChanged { scale = max(1, $0.magnification) }
                            .onEnded { _ in withAnimation { scale = 1 } })
                } else {
                    ProgressView().tint(.white)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("閉じる") { dismiss() } }
                if let image {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("画像", image: Image(uiImage: image)))
                    }
                }
            }
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                if let (data, _) = try? await URLSession.shared.data(from: url) { image = UIImage(data: data) }
            }
        }
    }
}

/// 吹き出し内に埋め込まれる「相談元タスク」の小カード。
private struct TaskCardChip: View {
    let card: ChatTaskCard
    let isMine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if !card.subject.isEmpty {
                    if isMine {
                        Text(card.subject).font(.caption.weight(.semibold))
                    } else {
                        SubjectBadge(subject: card.subject)
                    }
                }
                if !card.amount.isEmpty {
                    Text(card.amount).font(.caption)
                }
            }
            .foregroundStyle(isMine ? Color.white.opacity(0.9) : Theme.secondaryLabel)
            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isMine ? .white : Color.primary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isMine ? Color.white.opacity(0.18) : Color(UIColor.tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension View {
    func bubble(isMine: Bool) -> some View {
        self
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(isMine ? Theme.accent : Theme.secondaryBackground,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .foregroundStyle(isMine ? .white : Color.primary)
    }

    /// 長押しでコピー (iOS のメッセージと同じ)。
    func copyable(_ text: String) -> some View {
        modifier(CopyableModifier(text: text))
    }
}

private struct CopyableModifier: ViewModifier {
    let text: String
    @EnvironmentObject private var toast: ToastCenter

    func body(content: Content) -> some View {
        content.contextMenu {
            Button {
                UIPasteboard.general.string = text
                toast.show("コピーしました", systemImage: "doc.on.doc.fill", tint: Theme.accent, feel: .neutral)
            } label: {
                Label("コピー", systemImage: "doc.on.doc")
            }
        }
    }
}
