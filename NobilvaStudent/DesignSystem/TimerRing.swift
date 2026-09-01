import SwiftUI

/// タイマーの円環進捗表示。0.0〜1.0 の progress を渡す。
/// Canvas を使わず単純な Circle().trim() で軽量。
struct TimerRing: View {
    let progress: Double     // 0.0 ... 1.0
    let label: String
    let subLabel: String?
    var tint: Color = .accentColor
    var lineWidth: CGFloat = 12

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.separator.opacity(0.4), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.5), value: progress)

            VStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                if let subLabel {
                    Text(subLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
