import SwiftUI

@main
struct NobilvaStudentApp: App {
    @StateObject private var auth = AuthStore()
    @StateObject private var chatUnread = ChatUnreadStore()
    @StateObject private var router = AppRouter()
    @StateObject private var deepLink = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(chatUnread)
                .environmentObject(router)
                .environmentObject(deepLink)
                .tint(Theme.accent)
                .task { await auth.bootstrap() }
                // Universal Links (招待メールの /claim/* とリカバリメールの /recover/*)
                // が Web ではなくアプリで開かれると NSUserActivity 経由で届く。
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    if let url = activity.webpageURL { deepLink.handle(url: url) }
                }
                // 起動時に UserActivity で開かれた場合 (cold start) 用。
                .onOpenURL { url in deepLink.handle(url: url) }
        }
    }
}
