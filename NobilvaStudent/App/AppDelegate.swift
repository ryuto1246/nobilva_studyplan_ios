import UIKit
import SwiftUI

/// SwiftUI 単体では拾えない `didRegisterForRemoteNotificationsWithDeviceToken` を
/// 受け取るためだけの薄い AppDelegate。ここで得た device token は
/// `PushService.shared.registerDeviceToken(_:)` に渡す。実際のサーバ送信は
/// PushService 側 (Networking 経由) に委譲。
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushService.shared.registerDeviceToken(deviceToken)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Log.ui.error("APNs registration failed: \(String(describing: error))")
    }
}
