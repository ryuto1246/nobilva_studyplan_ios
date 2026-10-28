import SwiftUI

/// ログイン中のアカウントに登録されたパスキー一覧 + 追加/削除。
/// 削除は将来対応 (「危険なので confirm 挟むべき」の設計待ち)。今は追加のみ。
struct PasskeyManagementView: View {
    @EnvironmentObject var auth: AuthStore

    @State private var isRegistering = false
    @State private var justAdded = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Text("パスキーを登録すると、次回から Face ID や Touch ID ですぐにログインできます。この端末で 1 回登録すれば、同じ Apple ID の他のデバイス (iPad / Mac Safari 等) でも使えます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button {
                    Task { await add() }
                } label: {
                    HStack(spacing: 12) {
                        if isRegistering {
                            ProgressView()
                        } else {
                            Image(systemName: "plus.circle.fill").foregroundStyle(Theme.accent)
                        }
                        Text("この端末のパスキーを登録").bold()
                        Spacer()
                    }
                }
                .disabled(isRegistering)
            }
            if justAdded {
                Section {
                    Label("登録しました", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("パスキー")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert($errorMessage)
    }

    private func add() async {
        errorMessage = nil; justAdded = false
        isRegistering = true; defer { isRegistering = false }
        do {
            try await auth.addPasskey()
            justAdded = true
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "パスキーの登録に失敗しました。時間をおいて再度お試しください。"
        }
    }
}
