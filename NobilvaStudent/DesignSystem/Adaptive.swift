import SwiftUI

/// iPad など横に広い画面向けの調整をまとめる。
/// iPhone (compact) では何もしないので、各画面は付けるだけでよい。
enum Layout {
    /// 1 カラムで読む画面の本文の最大幅。これより広い画面では中央に寄せる。
    static let readableWidth: CGFloat = 680
    /// 2 カラムに並べる画面全体の最大幅。
    static let wideWidth: CGFloat = 1100
}

extension View {
    /// 本文を読みやすい幅に収めて中央に寄せる。画面がそれより狭ければそのまま。
    func readableWidth(_ maxWidth: CGFloat = Layout.readableWidth) -> some View {
        frame(maxWidth: maxWidth)
            .frame(maxWidth: .infinity)
    }
}
