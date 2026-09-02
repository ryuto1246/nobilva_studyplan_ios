import SwiftUI

/// タスク行の「相談する」ボタンから開くシート。
/// Web `TaskChatButton` と同じく 2 段構成:
///  1. 講師を選ぶ (単独講師でもタップして進む)
///  2. 相談内容を入力して送信
///
/// 送信は `ChatRepository.sendTaskConsultation` に委ね、成功時は onSuccess を呼び出す。
struct TaskChatSheet: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) var dismiss

    let card: ChatTaskCard
    /// 成功時のコールバック (親側で `notify` 等を出したい場合に使う)。
    var onSuccess: (() -> Void)? = nil

    @State private var partners: [ChatPartner]? = nil
    @State private var selectedTeacher: ChatPartner?
    @State private var message: String = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if let selectedTeacher {
                    composeStep(teacher: selectedTeacher)
                } else {
                    pickStep
                }
            }
            .background(Theme.groupedBackground.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル") { dismiss() }
                        .disabled(isSending)
                }
            }
            .task { await loadPartnersIfNeeded() }
            .errorAlert($errorMessage)
        }
    }

    // MARK: - Step 1: pick teacher

    private var pickStep: some View {
        List {
            Section {
                taskSummaryCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            } header: {
                Text("誰に相談しますか？").font(.headline).textCase(nil)
            }

            if let partners {
                if partners.isEmpty {
                    Section {
                        Text("相談できる講師がまだ登録されていません。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(partners) { p in
                            Button {
                                selectedTeacher = p
                            } label: {
                                HStack(spacing: 12) {
                                    ChatAvatar(name: p.displayName, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(p.displayName)
                                            .font(.body)
                                            .foregroundStyle(Color.primary)
                                        Text("タップして相談を開始")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                Section {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                }
            }
        }
        .navigationTitle("相談する")
    }

    // MARK: - Step 2: compose

    @ViewBuilder
    private func composeStep(teacher: ChatPartner) -> some View {
        Form {
            Section {
                taskSummaryCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
            } header: {
                Text("\(teacher.displayName) 先生に送信します").textCase(nil)
            }

            Section("相談内容") {
                TextField("多すぎて終わらなさそうです", text: $message, axis: .vertical)
                    .lineLimit(4...10)
                    .disabled(isSending)
            }

            Section {
                Button {
                    Task { await submit(teacher: teacher) }
                } label: {
                    HStack {
                        Spacer()
                        if isSending {
                            ProgressView().padding(.trailing, 6)
                        }
                        Text(isSending ? "送信中…" : "送信する").bold()
                        Spacer()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .navigationTitle("相談内容を入力")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("戻る") {
                    selectedTeacher = nil
                }
                .disabled(isSending)
            }
        }
    }

    // MARK: - Shared

    private var taskSummaryCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(card.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
            HStack(spacing: 6) {
                Circle().fill(Theme.subjectColor(card.subject)).frame(width: 8, height: 8)
                Text(card.subject).font(.caption).foregroundStyle(.secondary)
                if !card.amount.isEmpty {
                    Text("·").font(.caption).foregroundStyle(.secondary)
                    Text(card.amount).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Actions

    private func loadPartnersIfNeeded() async {
        if partners != nil { return }
        // まずキャッシュから即時表示
        if let cached = ChatRepository.cachedPartners() {
            partners = cached
        }
        do {
            let fresh = try await ChatRepository(api: auth.api).partners()
            partners = fresh
        } catch let e as APIError {
            if partners == nil { errorMessage = e.errorDescription }
        } catch {
            if partners == nil { errorMessage = "講師一覧の取得に失敗しました" }
        }
    }

    private func submit(teacher: ChatPartner) async {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSending = true; defer { isSending = false }
        do {
            _ = try await ChatRepository(api: auth.api).sendTaskConsultation(
                teacherId: teacher.teacherId, card: card, message: trimmed)
            onSuccess?()
            dismiss()
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "相談の送信に失敗しました"
        }
    }
}
