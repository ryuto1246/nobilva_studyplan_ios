import SwiftUI

extension View {
    /// パスキーボタンなど特別扱いしたいコントロール用の Liquid Glass ボタン。
    /// iOS 26 で `.buttonStyle(.glass)` を、以前は `.bordered` を使う。
    @ViewBuilder
    func glassOrBorderedButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
