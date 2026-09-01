import SwiftUI
import PhotosUI
import UIKit

struct ChatRoomView: View {
    @EnvironmentObject var auth: AuthStore
    let threadId: String
    let title: String

    @State private var messages: [ChatMessage] = []
    @State private var draft: String = ""
    @State private var isSending = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var pollingTask: Task<Void, Never>?
    @State private var photoPickerItem: PhotosPickerItem?

    // 送信直後の optimistic 表示用
    @State private var optimistic: [ChatMessage] = []

    var body: some View {
        VStack(spacing: 0) {
            messageScroll
            Divider()
            composer
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await load()
            await markRead()
            startPolling()
        }
        .onDisappear { stopPolling() }
        .errorAlert($errorMessage)
    }

    // MARK: - Message list

    private var messageScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(messages + optimistic) { m in
                        MessageBubble(message: m, isMine: isMineMessage(m))
                            .id(m.id)
                    }
                }
                .padding(12)
            }
            .background(Theme.groupedBackground)
            .refreshable { await load() }
            .onChange(of: (messages + optimistic).last?.id) { _, newId in
                if let id = newId {
                    withAnimation { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
    }

    private func isMineMessage(_ m: ChatMessage) -> Bool {
        guard let mine = auth.currentUser?.id else { return false }
        return m.senderId == mine
    }

    // MARK: - Composer (iMessage 風、iOS 26 Liquid Glass 対応)

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            attachButton
            inputCapsule
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// 左端の "+" ボタン。写真ピッカーを起動。
    /// composer は alignment: .bottom のため、Capsule 1 行時 (高さ ≒ 44) に
    /// + ボタン (34) の中心を Capsule の中心と揃えるため padding.bottom 5 を追加。
    /// 複数行に膨らんだ Capsule でも + は下端から 5px 上に固定される (iMessage 的)。
    private var attachButton: some View {
        PhotosPicker(selection: $photoPickerItem, matching: .images) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 34, height: 34)
                .foregroundStyle(.secondary)
                .background {
                    let shape = Circle()
                    if #available(iOS 26.0, *) {
                        shape.fill(.background).glassEffect(.regular, in: shape)
                    } else {
                        shape.fill(Theme.secondaryBackground)
                    }
                }
        }
        .padding(.bottom, 5)
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task { await handlePickedImage(item) }
        }
    }

    /// テキスト入力 + 内蔵送信ボタン。
    /// 形状は RoundedRectangle 固定 (cornerRadius: 22) にして、行数が増えても
    /// Capsule のように歪まない → 内側の送信ボタンが切れる問題を解消。
    /// 1 行時は高さ ≒ 44 で、22 の corner radius により見た目カプセルに近い。
    private var inputCapsule: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        let canSend = !isSending && !draft.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(alignment: .bottom, spacing: 6) {
            TextField("メッセージ", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...6)
                .submitLabel(.send)
                .padding(.leading, 16)
                // 1 行時に送信ボタンと垂直中心を合わせるための余白。
                // ボタン (30) + padding.bottom (7) = 37 で、TextField 側は
                // padding.vertical (11) * 2 + line height ≒ 22 = 44 に対して
                // ボタン中心 22.5 と TextField 中心 22 が概ね揃う。
                .padding(.vertical, 11)

            Button {
                Task { await send() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(canSend ? Theme.accent : Color.gray.opacity(0.45))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .padding(.trailing, 6)
            .padding(.bottom, 7)
        }
        .background {
            if #available(iOS 26.0, *) {
                shape.fill(.background).glassEffect(.regular, in: shape)
            } else {
                shape.fill(Theme.secondaryBackground)
            }
        }
        .overlay {
            shape.strokeBorder(Theme.separator.opacity(0.4), lineWidth: 0.5)
        }
        .clipShape(shape)
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                if Task.isCancelled { break }
                await load(silent: true)
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // MARK: - Actions

    private func load(silent: Bool = false) async {
        if !silent { isLoading = true }
        defer { if !silent { isLoading = false } }
        do {
            messages = try await ChatRepository(api: auth.api).messages(threadId: threadId)
            // optimistic の中でサーバに到達したものは差し引く (body が同じもの)
            optimistic = optimistic.filter { opt in
                !messages.contains { $0.body == opt.body && $0.imageUrl == opt.imageUrl }
            }
        } catch let e as APIError {
            if !silent { errorMessage = e.errorDescription }
        } catch {
            if !silent { errorMessage = "読み込みに失敗しました" }
        }
    }

    private func markRead() async {
        do { try await ChatRepository(api: auth.api).markRead(threadId: threadId) } catch {}
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        draft = ""
        isSending = true; defer { isSending = false }

        // optimistic
        let temp = ChatMessage(id: "temp-\(UUID().uuidString)", threadId: threadId, senderId: auth.currentUser?.id,
                                senderName: nil, body: text, imageUrl: nil, isAdminMessage: false,
                                createdAt: ISO8601DateFormatter().string(from: Date()))
        optimistic.append(temp)

        do {
            _ = try await ChatRepository(api: auth.api).send(threadId: threadId, body: text)
            await load(silent: true)
        } catch let e as APIError {
            errorMessage = e.errorDescription
            optimistic.removeAll { $0.id == temp.id }
        } catch {
            errorMessage = "送信に失敗しました"
            optimistic.removeAll { $0.id == temp.id }
        }
    }

    private func handlePickedImage(_ item: PhotosPickerItem) async {
        defer { photoPickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else { return }
        // 長辺 1600px + JPEG 圧縮
        guard let uiimg = UIImage(data: data),
              let jpeg = compressImage(uiimg, longEdge: 1600, quality: 0.7) else {
            errorMessage = "画像の変換に失敗しました"; return
        }
        do {
            _ = try await ChatRepository(api: auth.api).sendImage(
                threadId: threadId,
                imageData: jpeg,
                contentType: "image/jpeg",
                caption: nil
            )
            await load(silent: true)
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "画像の送信に失敗しました"
        }
    }

    private func compressImage(_ image: UIImage, longEdge: CGFloat, quality: CGFloat) -> Data? {
        let size = image.size
        let scale = min(1.0, longEdge / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        return resized.jpegData(compressionQuality: quality)
    }
}

// MARK: - Bubble

private struct MessageBubble: View {
    let message: ChatMessage
    let isMine: Bool

    /// 吹き出しと時刻を横並びに: iMessage 同様「自分は右端に吹き出し・その左に小さく時刻」、
    /// 「相手は左端に吹き出し・その右に小さく時刻」を出す。
    /// 縦方向の "隙間" を吹き出しの下に作らない。
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if isMine {
                Spacer(minLength: 40)
                timeText
                bubble
            } else {
                bubble
                timeText
                Spacer(minLength: 40)
            }
        }
    }

    private var timeText: some View {
        Group {
            if let ts = JSTDate.parseTimestamp(message.createdAt) {
                Text(JSTDate.time.string(from: ts))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        // ::task::{JSON} プレフィックスがあればカード付き吹き出し、無ければ通常の文字吹き出し。
        let parsed = message.body.flatMap { ChatTaskCardParser.parse($0) }
        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            if let url = message.imageUrl, let u = URL(string: url) {
                AsyncImage(url: u) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10).fill(Theme.groupedBackground)
                        .frame(width: 160, height: 120)
                        .overlay(ProgressView())
                }
                .frame(maxWidth: 240)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            if let parsed {
                VStack(alignment: .leading, spacing: 6) {
                    TaskCardChip(card: parsed.card, isMine: isMine)
                    if !parsed.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(parsed.message)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(isMine ? Theme.accent : Theme.secondaryBackground)
                .foregroundStyle(isMine ? .white : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else if let body = message.body, !body.isEmpty {
                Text(body)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(isMine ? Theme.accent : Theme.secondaryBackground)
                    .foregroundStyle(isMine ? .white : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

/// 吹き出し内に埋め込まれる「相談元タスク」の小カード。
/// Web 側 TaskCardMessage と同じ情報: 科目ドット + 科目名 + 量 + タイトル。
private struct TaskCardChip: View {
    let card: ChatTaskCard
    let isMine: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(Theme.subjectColor(card.subject))
                    .frame(width: 8, height: 8)
                Text(card.subject).font(.caption)
                if !card.amount.isEmpty {
                    Text("·").font(.caption).opacity(0.6)
                    Text(card.amount).font(.caption)
                }
            }
            .foregroundStyle(isMine ? Color.white.opacity(0.85) : Theme.secondaryLabel)

            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isMine ? .white : Color.primary)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isMine ? Color.white.opacity(0.15) : Color.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
