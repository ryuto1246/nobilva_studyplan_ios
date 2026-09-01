import SwiftUI

/// 計画アイテム / タスク 1 行の共通ビュー。
/// 目立たせたい 1 つだけ `prominent=true` にすると強調表示。
struct TodoRow: View {
    let title: String
    let subject: String
    let startTime: String?
    let durationMinutes: Int?
    let status: PlanItemStatus
    var prominent: Bool = false
    var onToggle: (() -> Void)? = nil
    var onStart: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 科目カラードット
            Circle()
                .fill(Theme.subjectColor(subject))
                .frame(width: 10, height: 10)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(prominent ? .headline : .body)
                    .strikethrough(status == .completed || status == .skipped)
                    .foregroundStyle(status == .completed ? Theme.secondaryLabel : Color.primary)

                HStack(spacing: 8) {
                    if !subject.isEmpty {
                        Label(subject, systemImage: "tag.fill")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    if let startTime, !startTime.isEmpty {
                        Label(startTime, systemImage: "clock")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryLabel)
                    }
                    if let durationMinutes {
                        Text("\(durationMinutes)分")
                            .font(.caption)
                            .foregroundStyle(Theme.tertiaryLabel)
                    }
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if let onStart, status != .completed {
                    Button(action: onStart) {
                        Image(systemName: "play.fill")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                }
                if let onToggle {
                    Button(action: onToggle) {
                        Image(systemName: status.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(status.isDone ? Theme.accent : Theme.secondaryLabel)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
    }
}
