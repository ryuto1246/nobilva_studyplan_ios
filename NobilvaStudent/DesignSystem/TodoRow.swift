import SwiftUI

/// 計画アイテム / タスク 1 行の共通ビュー。plan_items (PlanItem) と 未日付
/// tasks (StudentTask) と 期限切れ tasks を同じ骨格で描画する universal row。
///
/// レイアウト: [完了トグル (左)] [content: title + 科目/時刻/期限/分] [チャット] [取り組む]
///
/// iOS Reminders 準拠の並び: 左手で完了、右手でアクション (再生)。科目カラー
/// のドットは冗長 (Label 内の tag.fill アイコンで既に見えている) ので廃止。
///
/// - `startTime`: plan_items の予定時刻 (未日付タスクでは nil)
/// - `dueDate`  : タスクの締切 (plan_items では nil、未日付/期限切れタスクで表示)
struct TodoRow: View {
    let title: String
    let subject: String
    let startTime: String?
    let durationMinutes: Int?
    let dueDate: String?
    let status: PlanItemStatus
    var prominent: Bool = false
    var onToggle: (() -> Void)? = nil
    var onStart: (() -> Void)? = nil
    var onConsult: (() -> Void)? = nil

    /// 期限切れ / 未日付タスク (StudentTask) 向けの convenience init。
    /// TaskStatus → PlanItemStatus のマッピングを吸収する (`skipped` は無いので
    /// pending/inProgress/completed のみ)。
    init(
        title: String,
        subject: String,
        durationMinutes: Int?,
        dueDate: String? = nil,
        taskStatus: TaskStatus,
        prominent: Bool = false,
        onToggle: (() -> Void)? = nil,
        onStart: (() -> Void)? = nil,
        onConsult: (() -> Void)? = nil
    ) {
        self.title = title
        self.subject = subject
        self.startTime = nil
        self.durationMinutes = durationMinutes
        self.dueDate = dueDate
        switch taskStatus {
        case .pending: self.status = .pending
        case .inProgress: self.status = .inProgress
        case .completed: self.status = .completed
        }
        self.prominent = prominent
        self.onToggle = onToggle
        self.onStart = onStart
        self.onConsult = onConsult
    }

    /// PlanItem 向けの標準 init。dueDate は plan_items には無い概念なので隠す。
    init(
        title: String,
        subject: String,
        startTime: String?,
        durationMinutes: Int?,
        status: PlanItemStatus,
        prominent: Bool = false,
        onToggle: (() -> Void)? = nil,
        onStart: (() -> Void)? = nil,
        onConsult: (() -> Void)? = nil
    ) {
        self.title = title
        self.subject = subject
        self.startTime = startTime
        self.durationMinutes = durationMinutes
        self.dueDate = nil
        self.status = status
        self.prominent = prominent
        self.onToggle = onToggle
        self.onStart = onStart
        self.onConsult = onConsult
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // 左: 完了トグル (iOS Reminders パターン)
            if let onToggle {
                Button(action: onToggle) {
                    Image(systemName: status.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(status.isDone ? Theme.accent : Theme.secondaryLabel)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }

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
                    if let dueDate, !dueDate.isEmpty {
                        Label("期限 \(dueDate)", systemImage: "calendar")
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

            // 右: チャット → 取り組む (再生) の順
            HStack(spacing: 8) {
                if let onConsult, status != .completed {
                    Button(action: onConsult) {
                        Image(systemName: "message")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryLabel)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("このタスクについて相談する")
                }
                if let onStart, status != .completed {
                    Button(action: onStart) {
                        Image(systemName: "play.fill")
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.circle)
                    .controlSize(.small)
                    .accessibilityLabel("このタスクに取り組む")
                }
            }
        }
        .padding(.vertical, 8)
    }
}
