import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore

    @State private var identifier: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?
    @State private var showRecoverySheet = false

    enum Field { case identifier, password }

    @State private var showPasswordSection = false
    @State private var remembered: RememberedIdentity.Snapshot?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.groupedBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        passkeyPrimary
                        if remembered != nil {
                            switchAccountButton
                        }
                        if showPasswordSection {
                            passwordFallback
                        } else {
                            togglePasswordButton
                        }
                        recoveryButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showRecoverySheet) {
                RecoveryEmailSheet(auth: auth, prefillEmail: identifier.contains("@") ? identifier : "")
            }
            .errorAlert($errorMessage)
            .onAppear { loadRememberedIdentity() }
        }
    }

    private func loadRememberedIdentity() {
        guard remembered == nil, identifier.isEmpty else { return }
        if let snapshot = RememberedIdentity.read() {
            remembered = snapshot
            identifier = snapshot.identifier
        }
    }

    private var switchAccountButton: some View {
        Button {
            RememberedIdentity.forget()
            remembered = nil
            identifier = ""
            password = ""
        } label: {
            Text("違うアカウントで入る")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image("NobilvaLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 8) {
                if let name = remembered?.displayName, !name.isEmpty {
                    Text("おかえりなさい")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("\(name) さん")
                        .font(.largeTitle.bold())
                } else if remembered != nil {
                    Text("おかえりなさい")
                        .font(.largeTitle.bold())
                } else {
                    Text("ログイン")
                        .font(.largeTitle.bold())
                    Text("Face ID で素早くログインできます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var passkeyPrimary: some View {
        VStack(spacing: 12) {
            // 覚えている identifier がある場合は入力欄を出さない
            // (Face ID 一発で入れる方が「戻ってきた人」体験としてクリーン)。
            if remembered == nil {
                identifierField
            }
            Button {
                Task { await tryPasskey() }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView().tint(.white) }
                    Image(systemName: "faceid")
                    Text(remembered != nil ? "Face ID で続ける" : "Face ID でログイン").bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting)
        }
    }

    private var identifierField: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
        return HStack(spacing: 10) {
            Image(systemName: "at").foregroundStyle(.tertiary).frame(width: 22)
            TextField("ユーザーID / メールアドレス", text: $identifier)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($focused, equals: .identifier)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            if #available(iOS 26.0, *) {
                shape.fill(.background).glassEffect(.regular, in: shape)
            } else {
                shape.fill(Theme.secondaryBackground)
            }
        }
        .overlay { shape.strokeBorder(Theme.separator.opacity(0.35), lineWidth: 0.5) }
        .clipShape(shape)
    }

    private var togglePasswordButton: some View {
        Button {
            withAnimation { showPasswordSection = true }
        } label: {
            Text("パスワードでログインする")
                .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var passwordFallback: some View {
        VStack(spacing: 12) {
            // 覚えている場合は passkeyPrimary で identifier フィールドを隠しているので
            // ここで表示する (prefill 済み、確認用としても機能する)。
            if remembered != nil {
                identifierField
            }
            passwordField
            Button(action: submit) {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView() }
                    Text("パスワードでログイン").bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .glassOrBorderedButtonStyle()
            .disabled(isSubmitting || identifier.isEmpty || password.isEmpty)
        }
    }

    private var passwordField: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
        return HStack(spacing: 10) {
            Image(systemName: "lock.fill").foregroundStyle(.tertiary).frame(width: 22)
            Group {
                if isPasswordVisible {
                    TextField("パスワード", text: $password)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } else {
                    SecureField("パスワード", text: $password)
                }
            }
            .textContentType(.password)
            .submitLabel(.go)
            .focused($focused, equals: .password)
            .onSubmit(submit)

            Button {
                isPasswordVisible.toggle()
                focused = .password
            } label: {
                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background {
            if #available(iOS 26.0, *) {
                shape.fill(.background).glassEffect(.regular, in: shape)
            } else {
                shape.fill(Theme.secondaryBackground)
            }
        }
        .overlay { shape.strokeBorder(Theme.separator.opacity(0.35), lineWidth: 0.5) }
        .clipShape(shape)
    }

    private var recoveryButton: some View {
        Button {
            showRecoverySheet = true
        } label: {
            Text("ログインできない方はこちら")
                .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    // MARK: - Helpers

    private func submit() {
        Task { await performLogin() }
    }

    private func performLogin() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await auth.loginWithPassword(identifier: identifier.trimmingCharacters(in: .whitespaces), password: password)
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "ログインに失敗しました。時間をおいて再度お試しください。"
        }
    }

    private func tryPasskey() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let id = identifier.trimmingCharacters(in: .whitespaces)
            try await auth.loginWithPasskey(identifier: id.isEmpty ? nil : id)
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "Face ID でのログインに失敗しました。パスワードでも試してみてください。"
        }
    }
}

/// 「入れない時」用のメール送信シート。
/// サーバ側は登録済みメール一致時のみ Nobilva からリンク付きメールを送る。
/// レスポンスは常に成功形 (アカウント有無を漏らさない設計)。
/// リンクを踏むと Universal Link で iOS の RecoveryConsumeView が開き、
/// その中でパスキーを再登録する動線。
private struct RecoveryEmailSheet: View {
    let auth: AuthStore
    @Environment(\.dismiss) var dismiss

    @State private var email: String
    @State private var isSending = false
    @State private var noticeMessage: String?
    @State private var errorMessage: String?

    init(auth: AuthStore, prefillEmail: String) {
        self.auth = auth
        self._email = State(initialValue: prefillEmail)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("保護者のメールアドレス") {
                    TextField("example@email.com", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                Section {
                    Text("保護者のメールアドレスにログインし直すためのリンクを送ります。届いたリンクをタップするとアプリでパスキーを再登録できます。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let noticeMessage {
                    Section {
                        Label(noticeMessage, systemImage: "envelope.badge")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    }
                }
                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            if isSending { ProgressView() }
                            Text("送信").bold()
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSending || !isValid)
                }
            }
            .navigationTitle("メールで設定リンクを受け取る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("閉じる") { dismiss() } }
            }
            .errorAlert($errorMessage)
        }
    }

    private var isValid: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        // 完璧なメール正規表現は不可能なので、ざっくり "local@domain.tld" 形式か
        // だけチェック。過剰な pre-validation でユーザーを止めるより、サーバ側の
        // メール到達性 (登録有無) に任せた方が親切。
        guard let at = trimmed.firstIndex(of: "@") else { return false }
        let local = trimmed[..<at]
        let domain = trimmed[trimmed.index(after: at)...]
        return !local.isEmpty && domain.contains(".") && !domain.hasSuffix(".")
    }

    private func send() async {
        errorMessage = nil; noticeMessage = nil
        isSending = true; defer { isSending = false }
        do {
            let note = try await auth.requestRecoveryEmail(email.trimmingCharacters(in: .whitespaces))
            noticeMessage = note
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "送信に失敗しました。時間をおいて再度お試しください。"
        }
    }
}
