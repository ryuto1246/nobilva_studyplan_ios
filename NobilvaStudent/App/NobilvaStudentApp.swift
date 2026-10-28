import SwiftUI

@main
struct NobilvaStudentApp: App {
    // APNs の didRegisterForRemoteNotificationsWithDeviceToken を受け取るため
    // だけに UIApplicationDelegate を注入。他の SwiftUI ライフサイクルは触らない。
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var auth = AuthStore()
    @StateObject private var chatUnread = ChatUnreadStore()
    @StateObject private var router = AppRouter()
    @StateObject private var deepLink = DeepLinkRouter()
    @StateObject private var timer = StudyTimer()
    @StateObject private var toast = ToastCenter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .environmentObject(chatUnread)
                .environmentObject(router)
                .environmentObject(deepLink)
                .environmentObject(timer)
                .environmentObject(toast)
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
