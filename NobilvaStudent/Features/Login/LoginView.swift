import SwiftUI
import AuthenticationServices
import LocalAuthentication

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore

    @State private var identifier: String = ""
    @State private var password: String = ""
    @State private var isPasswordVisible: Bool = false
    @State private var isSubmitting = false
    @State private var isPasskeySubmitting = false
    @State private var errorMessage: String?
    @FocusState private var focused: Field?
    @State private var showRecoverySheet = false

    enum Field { case identifier, password }

    /// パスキーログインに失敗したときの案内 (キャンセルは除く)。
    /// パスワード欄の直上に inline 表示し、パスワードでの再挑戦へ促す。
    @State private var passkeyHint: String?
    @State private var remembered: RememberedIdentity.Snapshot?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.groupedBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        passkeySection
                        orDivider
                        passwordSection
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image("NobilvaLogo")
                .resizable()
                .scaledToFit()
                .frame(height: 64)
                .padding(.top, 8)
                .accessibilityLabel("Nobilva")
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
                }
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    // MARK: - Passkey (Face ID) section

    private var passkeySection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await tryPasskey() }
            } label: {
                HStack(spacing: 8) {
                    if isPasskeySubmitting { ProgressView().tint(.white) } else { Image(systemName: Self.biometry.symbol) }
                    Text(remembered != nil ? "\(Self.biometry.name)で続ける" : "\(Self.biometry.name)でログイン").bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || isPasskeySubmitting)

            if let hint = passkeyHint {
                passkeyHintView(hint)
            }

            if remembered != nil {
                switchAccountButton
            }
        }
    }

    private func passkeyHintView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.secondaryBackground)
        }
    }

    private var switchAccountButton: some View {
        Button {
            RememberedIdentity.forget()
            remembered = nil
            identifier = ""
            password = ""
            passkeyHint = nil
        } label: {
            Text("別のアカウントでログイン")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Divider

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Theme.separator.opacity(0.5)).frame(height: 0.5)
            Text("または")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Rectangle().fill(Theme.separator.opacity(0.5)).frame(height: 0.5)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Password section

    private var passwordSection: some View {
        VStack(spacing: 12) {
            identifierField
            passwordField
            Button(action: submit) {
                HStack(spacing: 8) {
                    if isSubmitting { ProgressView() }
                    Text("パスワードでログイン").bold()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.bordered)
            .disabled(isSubmitting || isPasskeySubmitting || identifier.isEmpty || password.isEmpty)
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
                .submitLabel(.next)
                .onSubmit { focused = .password }
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
        .contentShape(shape)
        .onTapGesture { focused = .identifier }
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
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPasswordVisible ? "パスワードを隠す" : "パスワードを表示")
        }
        .padding(.leading, 16)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .background {
            if #available(iOS 26.0, *) {
                shape.fill(.background).glassEffect(.regular, in: shape)
            } else {
                shape.fill(Theme.secondaryBackground)
            }
        }
        .overlay { shape.strokeBorder(Theme.separator.opacity(0.35), lineWidth: 0.5) }
        .clipShape(shape)
        .contentShape(shape)
        .onTapGesture { focused = .password }
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

    // MARK: - Actions

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
        passkeyHint = nil
        isPasskeySubmitting = true
        defer { isPasskeySubmitting = false }
        do {
            let id = identifier.trimmingCharacters(in: .whitespaces)
            try await auth.loginWithPasskey(identifier: id.isEmpty ? nil : id)
        } catch let e as ASAuthorizationError where e.code == .canceled {
            // ユーザーが Face ID シートを閉じたケース。案内は不要。
            return
        } catch let e as APIError where e.isNetwork {
            Haptics.error()
            passkeyHint = e.errorDescription
        } catch let e as APIError {
            // サーバ側の検証に失敗 (期限切れ・未登録の credential など)。
            Haptics.error()
            passkeyHint = "\(e.errorDescription ?? "ログインできませんでした。") パスワードでもログインできます。"
            focused = .password
        } catch {
            // 端末にパスキーが無い・システム側で中断された など。
            Haptics.error()
            passkeyHint = "この端末でパスキーを使えませんでした。下のパスワードでログインしてから、マイページ > パスキー・パスワードで登録できます。"
            focused = .password
        }
    }

    /// 端末の生体認証に合わせた表記。生体認証が無い端末は「パスキー」。
    private static let biometry: (name: String, symbol: String) = {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch ctx.biometryType {
        case .faceID: return ("Face ID ", "faceid")
        case .touchID: return ("Touch ID ", "touchid")
        case .opticID: return ("Optic ID ", "opticid")
        default: return ("パスキー", "person.badge.key")
        }
    }()
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
