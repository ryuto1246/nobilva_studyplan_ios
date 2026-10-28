import SwiftUI

/// 今日画面の先頭に 1 件だけ大きく出す「まずはこれ」。
/// 取り組む (主) / 完了 (副) / 相談 (補助) の 3 操作を、迷わない大きさで並べる。
struct FocusCard: View {
    let item: StudyItem
    /// 別の計測中なら「取り組む」ではなく「タイマーを開く」にする。
    var isTiming = false
    let onStart: () -> Void
    let onComplete: () -> Void
    let onConsult: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("まずはこれ")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityAddTraits(.isHeader)
                StudyItemText(item: item, titleFont: .title2.bold())
                if let rationale = item.rationale, !rationale.isEmpty {
                    Text(rationale)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { buttons }
                VStack(spacing: 12) { buttons }
            }

            Button(action: onConsult) {
                Label("先生に相談する", systemImage: "bubble.left")
                    .font(.subheadline)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.borderless)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var buttons: some View {
        PrimaryButton(isTiming ? "タイマーを開く" : "取り組む", systemImage: isTiming ? "timer" : "play.fill", action: onStart)
        SecondaryButton("完了", systemImage: "checkmark", action: onComplete)
    }
}
