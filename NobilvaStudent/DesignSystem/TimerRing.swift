import SwiftUI

/// タイマーの円環進捗表示。0.0〜1.0 の progress を渡す。
/// Canvas を使わず単純な Circle().trim() で軽量。
struct TimerRing: View {
    let progress: Double     // 0.0 ... 1.0
    let label: String
    let subLabel: String?
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 12

    /// 文字サイズ設定に合わせて拡大する (上限はリングの内側に収まる程度)。
    @ScaledMetric(relativeTo: .largeTitle) private var digitSize: CGFloat = 52

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.separator.opacity(0.4), lineWidth: lineWidth)
            // progress が 0 のときに線の端の丸だけが残って見えないようにする。
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .opacity(progress > 0.001 ? 1 : 0)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)

            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: min(digitSize, 72), weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if let subLabel {
                    Text(subLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(lineWidth * 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([label, subLabel].compactMap { $0 }.joined(separator: "、"))
    }
}
