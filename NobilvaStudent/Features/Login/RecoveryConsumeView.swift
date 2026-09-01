import SwiftUI

/// 保護者メールに届いたリカバリリンクを Universal Link でタップした際の到着画面。
///
/// フロー:
///   1. NobilvaStudentApp が URL を受け取り、token を抽出
///   2. AuthStore.consumeRecoveryToken で token 消費 → セッション確立
///   3. 成功 → PasskeyManagementView を出して「新しいパスキーを登録する」導線を提示
///   4. 失敗 → メッセージを出してログイン画面へ戻す
struct RecoveryConsumeView: View {
    @EnvironmentObject var auth: AuthStore
    let token: String
    let onDismiss: () -> Void

    @State private var phase: Phase = .verifying
    @State private var errorMessage: String?

    enum Phase {
        case verifying
        case succeeded
        case failed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.groupedBackground.ignoresSafeArea()
                switch phase {
                case .verifying:
                    ProgressView("リンクを確認中…")
                case .succeeded:
                    successState
                case .failed:
                    failedState
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await verify() }
    }

    private var successState: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64)).foregroundStyle(.green)
            Text("ログインしました").font(.title2.bold())
            Text("この端末にパスキーを登録すると、次回から Face ID ですぐに入れます。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button {
                Task { await registerPasskey() }
            } label: {
                HStack {
                    Image(systemName: "faceid")
                    Text("パスキーを登録").bold()
                }
                .frame(maxWidth: .infinity).padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            Button("あとで") { onDismiss() }
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
    }

    private var failedState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundStyle(.orange)
            Text("リンクを確認できませんでした").font(.title3.bold())
            if let errorMessage {
                Text(errorMessage).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            Text("メールから最新のリンクを開き直してください。").font(.footnote).foregroundStyle(.tertiary)
            Button("戻る") { onDismiss() }.padding(.top, 8)
        }
        .padding(.horizontal, 32)
    }

    private func verify() async {
        do {
            try await auth.consumeRecoveryToken(token)
            phase = .succeeded
        } catch let e as APIError {
            errorMessage = e.errorDescription
            phase = .failed
        } catch {
            errorMessage = "通信に失敗しました"
            phase = .failed
        }
    }

    private func registerPasskey() async {
        do {
            try await auth.addPasskey()
            onDismiss()
        } catch {
            // 失敗しても既にログインは済んでいるのでそのまま dismiss。
            // 後で Settings > セキュリティ から再登録できる。
            onDismiss()
        }
    }
}
