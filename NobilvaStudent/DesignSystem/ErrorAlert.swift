import SwiftUI

/// アプリ内のエラーメッセージ表示を「ダイアログ (alert)」に統一するための共通 modifier。
///
/// - `@State private var errorMessage: String?` を持ち、非 nil の間だけ
///   同じ見た目のアラートが出るようにする。
/// - 中央寄せのカード + 再読み込みボタン、インラインのエラー Text 等の
///   バラバラだった実装をここに集約。
extension View {
    /// エラー用アラート。message を nil に戻すのは中で自動。
    func errorAlert(_ message: Binding<String?>, title: String = "エラー") -> some View {
        alert(title, isPresented: Binding(
            get: { message.wrappedValue != nil },
            set: { if !$0 { message.wrappedValue = nil } }
        )) {
            Button("OK") { message.wrappedValue = nil }
        } message: {
            Text(message.wrappedValue ?? "")
        }
    }
}
