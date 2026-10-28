import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var deepLink: DeepLinkRouter
    @EnvironmentObject var toast: ToastCenter
    @EnvironmentObject var timer: StudyTimer

    var body: some View {
        content
            // タブバー (約 64pt) と、計測中はその上の計測バー (約 58pt) を避ける。
            .toastHost(toast, bottomInset: 72 + (timer.hasSession ? 58 : 0))
            // Recovery は authenticated / unauthenticated どちらの状態でも fullScreen で被せる。
            // token 消費で phase が .authenticated に切り替わり、成功画面で dismiss → MainTabView へ。
            .fullScreenCover(isPresented: recoveryBinding) {
                if case let .recovery(token) = deepLink.pending {
                    RecoveryConsumeView(token: token) {
                        deepLink.clear()
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch auth.phase {
        case .bootstrapping:
            SplashView()
        case .unauthenticated:
            // Claim ディープリンクが立っていれば LoginView より優先。
            if case let .claim(token) = deepLink.pending {
                ClaimView(token: token)
                    // claim 成功 → phase が .authenticated に切り替わって content が
                    // MainTabView になる。deepLink はもう不要なのでクリア。
                    .onDisappear { deepLink.clear() }
            } else {
                LoginView()
            }
        case .authenticated:
            MainTabView()
                .task { await PushService.shared.requestAuthorizationAndRegister() }
        }
    }

    private var recoveryBinding: Binding<Bool> {
        Binding(
            get: {
                if case .recovery = deepLink.pending { return true }
                return false
            },
            set: { newValue in if !newValue { deepLink.clear() } }
        )
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            Theme.groupedBackground.ignoresSafeArea()
            VStack(spacing: 20) {
                Image("NobilvaLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 200)
                ProgressView()
            }
        }
    }
}
