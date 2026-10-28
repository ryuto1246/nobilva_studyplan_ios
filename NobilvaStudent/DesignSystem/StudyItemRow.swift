import SwiftUI

/// 「やること」1 行の共通ビュー。計画アイテム・期限切れタスク・日付未定タスクすべてで使う。
///
/// レイアウト: [完了トグル] [タイトル / 遅れ・科目・分量] [▶︎]
/// - 行本体のタップが主操作 (取り組む / 編集)。完了トグルだけ独立したボタン。
/// - 相談などの副操作は長押しメニューにまとめ、行を軽く保つ。
/// - 2 行目は 1 つの Text なので、狭い幅や大きな文字でも単語の途中で割れない。
struct StudyItemRow: View {
    let item: StudyItem
    /// nil なら完了トグルを出さない (読み取り専用の行)。
    var onToggle: (() -> Void)?
    /// 行タップ時の操作。nil ならタップ不可。
    var onTap: (() -> Void)?
    /// 行の右端に ▶︎ を出すか (onTap が「取り組む」のとき true)。
    var showsStartIcon = true
    var onConsult: (() -> Void)?
    var onEdit: (() -> Void)?

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            if let onToggle {
                CompletionToggle(isDone: item.isDone, title: item.title, action: onToggle)
            }
            if let onTap {
                Button(action: onTap) { rowContent }
                    .buttonStyle(.plain)
                    .accessibilityHint(showsStartIcon && !item.isDone ? "タイマーを開きます" : "")
            } else {
                // 読み取り専用の行は Button で包まない (VoiceOver が「淡色表示」と読むため)。
                rowContent.accessibilityElement(children: .combine)
            }
        }
        .padding(.leading, onToggle == nil ? 12 : 0)
        .padding(.trailing, 12)
        .contextMenu {
            if let onTap, showsStartIcon, !item.isDone {
                Button { onTap() } label: { Label("取り組む", systemImage: "play.fill") }
            }
            if let onConsult, !item.isDone {
                Button { onConsult() } label: { Label("先生に相談する", systemImage: "bubble.left") }
            }
            if let onEdit {
                Button { onEdit() } label: { Label("編集", systemImage: "pencil") }
            }
            if let onToggle {
                Button { onToggle() } label: {
                    item.isDone
                        ? Label("未完了に戻す", systemImage: "arrow.uturn.backward")
                        : Label("完了にする", systemImage: "checkmark.circle")
                }
            }
        }
    }
}

private extension StudyItemRow {
    var rowContent: some View {
        HStack(alignment: .center, spacing: 8) {
            StudyItemText(item: item)
            Spacer(minLength: 0)
            if onTap != nil, showsStartIcon, !item.isDone {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// タイトルと 2 行目 (科目バッジ・遅れ・分量)。行とフォーカスカードで共有。
struct StudyItemText: View {
    let item: StudyItem
    var titleFont: Font = .body
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(titleFont)
                .fixedSize(horizontal: false, vertical: true)
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? Theme.secondaryLabel : Color.primary)
                .multilineTextAlignment(.leading)
            // アクセシビリティ用の大きな文字では、バッジと詳細を縦に積む。
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { badge; wrappedDetail }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) { badge; wrappedDetail }
                }
            }
            .font(.subheadline)
        }
    }

    @ViewBuilder
    private var badge: some View {
        if !item.subject.isEmpty {
            SubjectBadge(subject: item.subject, isMuted: item.isDone)
        }
    }

    /// 省略せずに折り返す (ボタンのラベル内では高さが足りず「…」になりやすいため)。
    private var wrappedDetail: some View {
        detail.fixedSize(horizontal: false, vertical: true)
    }

    private var detail: Text {
        let rest = Text(item.detailText).foregroundStyle(Theme.secondaryLabel)
        guard let overdue = item.overdueLabel, !item.isDone else { return rest }
        return Text(overdue).foregroundStyle(.red).bold() + Text(" · ").foregroundStyle(Theme.secondaryLabel) + rest
    }
}

/// 科目の色付きラベル (Web の bg-*-100 text-*-800 相当)。
struct SubjectBadge: View {
    let subject: String
    var isMuted = false

    var body: some View {
        let color = isMuted ? Color.gray : Theme.subjectColor(subject)
        Text(subject)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .fixedSize()
            .accessibilityLabel("科目 \(subject)")
    }
}

/// 丸いチェック。見た目は 24pt、タップ領域は 44pt。
struct CompletionToggle: View {
    let isDone: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isDone ? Theme.accent : Theme.secondaryLabel)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDone ? "未完了に戻す" : "完了にする")
        .accessibilityValue(isDone ? "完了" : "未完了")
    }
}

/// 行を Card 内で区切り線付きで並べる。
struct StudyItemList<Row: View>: View {
    let items: [StudyItem]
    @ViewBuilder let row: (StudyItem) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                row(item)
                if i != items.count - 1 {
                    Divider().padding(.leading, 56)
                }
            }
        }
        .background(Theme.secondaryBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
    }
}
