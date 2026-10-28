import SwiftUI

/// 面談 1 件の概要 (タイトル・日時・状態)。今日画面のカードと面談一覧で共有。
struct MeetingSummary: View {
    let meeting: Meeting
    var showsCountdown = true

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(meeting.title)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if meeting.displayStatus.label != "予定" {
                    StatusBadge(text: meeting.displayStatus.label, tint: badgeTint)
                }
            }
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var subtitle: String {
        var parts = [meeting.scheduleLabel]
        if showsCountdown, let c = meeting.countdownLabel { parts.append(c) }
        if let name = meeting.teacher?.displayName { parts.append(name) }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var badgeTint: Color {
        meeting.displayStatus.tint == "orange" ? .orange : .secondary
    }
}

/// 小さな状態ラベル。
struct StatusBadge: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.15), in: Capsule())
    }
}
