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

/// iPad の「左に一覧・右に詳細」の 2 カラム。
///
/// NavigationSplitView は iPadOS 26 で左列が浮いたガラスのパネルになり、上のタブバーの下に
/// 潜り込んで上端が途切れて見える。今日画面と同じ背景・タイトル位置にそろえるため、
/// 2 つの NavigationStack を横に並べるだけの素朴な形にしている。
struct TwoColumnLayout<Sidebar: View, Detail: View>: View {
    var sidebarWidth: CGFloat = 380
    @ViewBuilder var sidebar: Sidebar
    @ViewBuilder var detail: Detail

    var body: some View {
        HStack(spacing: 0) {
            NavigationStack { sidebar }
                .frame(width: sidebarWidth)
            Divider()
                .ignoresSafeArea()
            NavigationStack { detail }
                .frame(maxWidth: .infinity)
        }
        .background(Theme.groupedBackground.ignoresSafeArea())
    }
}
