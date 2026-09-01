import SwiftUI

/// Liquid Glass 系マテリアルの唯一の適用箇所。
/// - iOS 26+ では `glassEffect(.regular, in:)` を使い本物の Liquid Glass に
/// - iOS 17-25 では Material.bar に fallback
/// このヘルパー以外の場所で `.background(.ultraThinMaterial)` などを追加しないこと。
/// パフォーマンス上、glass は 1 画面につき 1〜2 レイヤーに抑える方針。
struct GlassBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: Rectangle())
        } else {
            content.background(.bar)
        }
    }
}

extension View {
    /// タブバー/ナビバー等の背景に薄いガラス風マテリアルを敷く。
    /// iOS 26 以降は Liquid Glass、それ未満は Material.bar。
    func glassBar() -> some View {
        modifier(GlassBar())
    }

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
