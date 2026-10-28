import SwiftUI

/// ログイン中のアカウントのパスワードを設定 or 変更。
/// パスキー only ユーザーが手動で追加するケース、既存パスワードを更新するケース、
/// 両方をカバーする。副作用でサーバ側の password_enabled=TRUE が立つ。
struct PasswordChangeView: View {
    @EnvironmentObject var auth: AuthStore

    @State private var newPassword: String = ""
    @State private var confirm: String = ""
    @State private var isSaving = false
    @State private var saved = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                SecureField("新しいパスワード", text: $newPassword)
                    .textContentType(.newPassword)
                SecureField("もう一度入力", text: $confirm)
                    .textContentType(.newPassword)
            } footer: {
                Text("8 文字以上で設定してください。iCloud キーチェーンに保存すれば、次回から自動入力されます。")
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if isSaving { ProgressView() }
                        Text("保存").bold()
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving || !isValid)
            }
            if saved {
                Section {
                    Label("保存しました", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
        }
        .navigationTitle("パスワード")
        .navigationBarTitleDisplayMode(.inline)
        .errorAlert($errorMessage)
    }

    private var isValid: Bool {
        newPassword.count >= 8 && newPassword == confirm
    }

    private func save() async {
        errorMessage = nil; saved = false
        isSaving = true; defer { isSaving = false }
        do {
            try await auth.setOrChangePassword(newPassword)
            saved = true
            newPassword = ""; confirm = ""
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "保存に失敗しました。時間をおいて再度お試しください。"
        }
    }
}
