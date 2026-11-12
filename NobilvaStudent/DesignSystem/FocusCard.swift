import SwiftUI

/// 今日画面の先頭に 1 件だけ大きく出す「まずはこれ」。
/// 取り組む (主) / 完了 (副) / スキップ (補助) の 3 操作を、迷わない大きさで並べる。
/// 計画アイテムでは右端がスキップ (相談はスキップのシートの先頭から行ける)。
/// スキップできないタスクでは、右端は今までどおり相談。
struct FocusCard: View {
    let item: StudyItem
    /// 別の計測中なら「取り組む」ではなく「タイマーを開く」にする。
    var isTiming = false
    let onStart: () -> Void
    let onComplete: () -> Void
    let onConsult: () -> Void
    /// 「やらない (スキップ)」。計画アイテムのときだけ渡す。渡すと右端の相談ボタンと入れ替わる。
    var onSkip: (() -> Void)?

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

            // 補助の操作は主操作ではないので、同じ列の右端に小さなアイコンボタンとして置く。
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { buttons; trailingButton }
                VStack(spacing: 10) { buttons; trailingButton }
            }
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
    private var trailingButton: some View {
        if let onSkip {
            iconButton("forward.end", label: "やらない（スキップ）", action: onSkip)
        } else {
            iconButton("bubble.left", label: "先生に相談する", action: onConsult)
        }
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(minWidth: 34, minHeight: 34)
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private var buttons: some View {
        PrimaryButton(isTiming ? "タイマーを開く" : "取り組む", systemImage: isTiming ? "timer" : "play.fill", action: onStart)
        SecondaryButton("完了", systemImage: "checkmark", action: onComplete)
    }
}
