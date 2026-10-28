import SwiftUI

/// タイマーを使わずに「完了」したとき、かかった時間を記録するよう促すシート。
/// 記録すると学習記録に残り、そのまま完了になる。記録せずに完了することもできる。
struct RecordOnCompleteSheet: View {
    enum Choice { case record(minutes: Int), skip }

    let item: StudyItem
    let onChoose: (Choice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int

    init(item: StudyItem, onChoose: @escaping (Choice) -> Void) {
        self.item = item
        self.onChoose = onChoose
        // 予定の時間を初期値にする (5 分刻みにそろえる)。
        _minutes = State(initialValue: max(5, (item.minutes / 5) * 5))
    }

    /// よく使う長さ 4 つ。予定の時間が含まれていなければ差し込む。
    private var presets: [Int] {
        let planned = max(5, (item.minutes / 5) * 5)
        var base = [15, 30, 45, 60]
        if !base.contains(planned) { base[base.count - 1] = planned }
        return base.sorted()
    }

    /// チップ用の短い表記 ("15分" / "1時間" / "1.5時間")。
    private func chipLabel(_ m: Int) -> String {
        if m < 60 { return "\(m)分" }
        return m % 60 == 0 ? "\(m / 60)時間" : formatMinutes(m)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("どれくらい取り組みましたか？")
                        .font(.title3.bold())
                    StudyItemText(item: item)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(formatMinutes(minutes))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold).monospacedDigit())
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .contentTransition(.numericText())
                    HStack(spacing: 8) {
                        ForEach(presets, id: \.self) { m in
                            Button {
                                Haptics.selection()
                                withAnimation(.snappy) { minutes = m }
                            } label: {
                                Text(chipLabel(m))
                                    .font(.subheadline.weight(.semibold))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .frame(maxWidth: .infinity, minHeight: 32)
                            }
                            .buttonStyle(.bordered)
                            .tint(m == minutes ? Theme.accent : .secondary)
                        }
                    }
                    Stepper("5分ずつ調整", value: $minutes.animation(.snappy), in: 5...600, step: 5)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(spacing: 4) {
                    PrimaryButton("\(formatMinutes(minutes))を記録して完了", systemImage: "checkmark") {
                        dismiss()
                        onChoose(.record(minutes: minutes))
                    }
                    Button("記録せずに完了") {
                        dismiss()
                        onChoose(.skip)
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                }
            }
            .padding(20)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
