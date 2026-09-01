import Foundation
import SwiftUI

/// Universal Links (`https://studyplan.nobilva.jp/claim/*` と `/recover/*`) を
/// タップした時のルーティング先を保持する ObservableObject。
///
/// RootView が phase に加えて pending を見て、
///   - .claim: unauthenticated 中でも ClaimView を出す
///   - .recovery: authenticated / unauthenticated どちらでも RecoveryConsumeView を出す
/// のように分岐する。
@MainActor
final class DeepLinkRouter: ObservableObject {
    enum Pending: Equatable {
        case claim(token: String)
        case recovery(token: String)
    }

    @Published var pending: Pending?

    /// AASA で許可されている 2 パターンだけ受け付ける。それ以外の URL は無視。
    func handle(url: URL) {
        guard url.host == "studyplan.nobilva.jp" else { return }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 2 else { return }
        let (kind, token) = (parts[0], parts[1])
        guard !token.isEmpty else { return }
        switch kind {
        case "claim":    pending = .claim(token: token)
        case "recover":  pending = .recovery(token: token)
        default: return
        }
    }

    func clear() { pending = nil }
}
