import SwiftUI

struct ChatThreadListView: View {
    @EnvironmentObject var auth: AuthStore

    @State private var threads: [ChatThread] = []
    @State private var partners: [ChatPartner] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if threads.isEmpty && partners.isEmpty && !isLoading {
                    ContentUnavailableView("チャット可能な相手がいません",
                                           systemImage: "bubble.left.and.bubble.right",
                                           description: Text("担当講師とのチャットはここに表示されます"))
                }
                if !threads.isEmpty {
                    Section("スレッド") {
                        ForEach(threads) { t in
                            NavigationLink {
                                ChatRoomView(threadId: t.id, title: t.teacherName ?? "チャット")
                                    .environmentObject(auth)
                            } label: {
                                threadRow(t)
                            }
                        }
                    }
                }
                if !partners.isEmpty {
                    Section("チャット可能な講師") {
                        ForEach(partners) { p in
                            Button {
                                Task { await openWithPartner(p) }
                            } label: {
                                HStack(spacing: 10) {
                                    ChatAvatar(name: p.displayName, size: 32)
                                    Text(p.displayName)
                                    Spacer()
                                    Image(systemName: "plus.bubble").foregroundStyle(Theme.accent)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("チャット")
            .task {
                // まずキャッシュから即座に表示
                if threads.isEmpty, let cached = ChatRepository.cachedThreads() {
                    threads = cached
                }
                if partners.isEmpty, let cached = ChatRepository.cachedPartners() {
                    let existing = Set(threads.compactMap { $0.teacherId })
                    partners = cached.filter { !existing.contains($0.id) }
                }
                await load()
            }
            .refreshable { await load() }
            .overlay { if isLoading && threads.isEmpty { ProgressView() } }
            .errorAlert($errorMessage)
        }
    }

    private func threadRow(_ t: ChatThread) -> some View {
        HStack(spacing: 10) {
            ChatAvatar(name: t.teacherName ?? "?", size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(t.teacherName ?? "講師").font(.subheadline).bold()
                Text(previewText(t.lastMessageBody))
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let n = t.unreadCount, n > 0 {
                Text("\(n)")
                    .font(.caption2).bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.red).clipShape(Capsule())
            }
        }
    }

    /// nil / 空文字を "(メッセージなし)"、`::task::` prefix を「【相談】…」に整形。
    private func previewText(_ body: String?) -> String {
        guard let body, !body.isEmpty else { return "(メッセージなし)" }
        return ChatTaskCardParser.preview(body)
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            async let t = ChatRepository(api: auth.api).threads()
            async let p = ChatRepository(api: auth.api).partners()
            let (tt, pp) = try await (t, p)
            threads = tt
            // partners のうち既にスレッドがある人は隠す
            let existing = Set(tt.compactMap { $0.teacherId })
            partners = pp.filter { !existing.contains($0.id) }
        } catch let e as APIError {
            // キャッシュがすでに表示されている時はエラーを見せない
            if threads.isEmpty && partners.isEmpty {
                errorMessage = e.errorDescription
            }
        } catch {
            if threads.isEmpty && partners.isEmpty {
                errorMessage = "読み込みに失敗しました"
            }
        }
    }

    private func openWithPartner(_ p: ChatPartner) async {
        do {
            let resp = try await ChatRepository(api: auth.api).createOrGetThread(teacherId: p.id)
            _ = resp
            await load()
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "スレッドを開けませんでした"
        }
    }
}
