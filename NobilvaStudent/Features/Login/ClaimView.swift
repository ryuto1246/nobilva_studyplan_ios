import SwiftUI

/// 招待メールから Universal Link で開かれたときの初回登録画面。
///
/// フロー:
///   1. NobilvaStudentApp が userActivity を受け取り、claim token を抽出
///   2. AuthStore.fetchClaimPreview で token 検証 + 生徒情報表示
///   3. ユーザー名入力 → 「パスキーで登録」→ 失敗時に「パスワードで登録」fallback
///   4. 成功時は AuthStore.phase = .authenticated に変わり RootView が MainTabView へ
struct ClaimView: View {
    @EnvironmentObject var auth: AuthStore
    let token: String

    @State private var preview: AuthStore.ClaimTokenPreview?
    @State private var loadError: String?
    @State private var isLoading = true

    @State private var username: String = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var showPasswordFallback = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.groupedBackground.ignoresSafeArea()
                if isLoading {
                    ProgressView("確認中…")
                } else if let preview {
                    content(for: preview)
                } else if let loadError {
                    errorState(loadError)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .errorAlert($errorMessage)
        }
        .task { await load() }
    }

    private func content(for preview: AuthStore.ClaimTokenPreview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(preview: preview)
                usernameCard
                primaryButton
                if showPasswordFallback {
                    passwordFallbackSection
                } else {
                    fallbackHint
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 32)
        }
    }

    private func header(preview: AuthStore.ClaimTokenPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image("NobilvaLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
            VStack(alignment: .leading, spacing: 8) {
                Text("ようこそ").font(.title.bold())
                Text("\(preview.studentDisplayName) さんのアカウントをセットアップします。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var usernameCard: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 8) {
                Text("ユーザーID")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                HStack(spacing: 10) {
                    Image(systemName: "at").foregroundStyle(.tertiary).frame(width: 22)
                    TextField("好きな名前 (英数字で 3〜24 文字)", text: $username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
            .background {
                if #available(iOS 26.0, *) {
                    shape.fill(.background).glassEffect(.regular, in: shape)
                } else {
                    shape.fill(Theme.secondaryBackground)
                }
            }
            .overlay { shape.strokeBorder(Theme.separator.opacity(0.35), lineWidth: 0.5) }
            .clipShape(shape)

            // 未入力の間はヒントを出さない (触っていないのに赤字が出るとびっくりする)。
            // 入力があって かつ 無効な時だけ、優しめの理由を出す。
            if !username.isEmpty && !isValidUsername {
                Text(usernameHint)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var usernameHint: String {
        if username.count < 3 { return "3 文字以上で入力してください" }
        if username.count > 24 { return "24 文字以内で入力してください" }
        return "英数字と ._- のみ使用できます"
    }

    private var primaryButton: some View {
        Button {
            Task { await registerWithPasskey() }
        } label: {
            HStack(spacing: 8) {
                if isSubmitting { ProgressView().tint(.white) }
                Image(systemName: "faceid")
                Text("パスキーで登録").bold()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isSubmitting || !isValidUsername)
    }

    private var fallbackHint: some View {
        Button {
            withAnimation { showPasswordFallback = true }
        } label: {
            Text("パスキーが使えない場合はパスワードで登録")
                .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    @State private var password: String = ""
    @State private var passwordConfirm: String = ""

    private var passwordFallbackSection: some View {
        VStack(spacing: 12) {
            Divider()
            Text("パスワードで登録").font(.subheadline.bold()).frame(maxWidth: .infinity, alignment: .leading)
            SecureField("パスワード (8 文字以上)", text: $password)
                .textContentType(.newPassword)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 10))
            SecureField("もう一度入力", text: $passwordConfirm)
                .textContentType(.newPassword)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 10))
            Button {
                Task { await registerWithPassword() }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView() }
                    Text("パスワードで登録する").bold()
                }
                .frame(maxWidth: .infinity)
            }
            .glassOrBorderedButtonStyle()
            .disabled(isSubmitting || !isValidUsername || !isValidPassword)
        }
        .padding(.top, 8)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Text("契約担当者にお問い合わせください。").font(.footnote).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Validation

    private var isValidUsername: Bool {
        let regex = try? NSRegularExpression(pattern: "^[A-Za-z0-9_.-]{3,24}$")
        let range = NSRange(username.startIndex..<username.endIndex, in: username)
        return regex?.firstMatch(in: username, range: range) != nil
    }

    private var isValidPassword: Bool {
        password.count >= 8 && password == passwordConfirm
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            preview = try await auth.fetchClaimPreview(token: token)
        } catch let e as APIError {
            loadError = e.errorDescription ?? "リンクを確認できませんでした"
        } catch {
            loadError = "通信に失敗しました"
        }
    }

    private func registerWithPasskey() async {
        errorMessage = nil
        isSubmitting = true; defer { isSubmitting = false }
        do {
            try await auth.claimWithPasskey(token: token, username: username)
            if let preview {
                RememberedIdentity.updateDisplayName(preview.studentDisplayName)
            }
        } catch let e as APIError {
            errorMessage = e.errorDescription
            // パスキーが端末側で使えない (Face ID 未設定 / iOS バージョン等)
            // 場合はパスワードフォールバックを自動で開く。
            withAnimation { showPasswordFallback = true }
        } catch {
            errorMessage = "パスキー登録に失敗しました。パスワードでも登録できます。"
            withAnimation { showPasswordFallback = true }
        }
    }

    private func registerWithPassword() async {
        errorMessage = nil
        isSubmitting = true; defer { isSubmitting = false }
        do {
            try await auth.claimWithPassword(token: token, username: username, password: password)
            if let preview {
                RememberedIdentity.updateDisplayName(preview.studentDisplayName)
            }
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "登録に失敗しました。時間をおいて再度お試しください。"
        }
    }
}
