import SwiftUI

/// 画面全体の読み込み中表示。
struct LoadingStateView: View {
    var body: some View {
        ProgressView()
            .controlSize(.large)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 読み込みに失敗し、表示できるデータも無いときの表示。
struct RetryStateView: View {
    var message: String = "通信状況を確認して、もう一度お試しください。"
    let retry: () async -> Void

    var body: some View {
        ContentUnavailableView {
            Label("読み込めませんでした", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("再読み込み") { Task { await retry() } }
                .buttonStyle(.borderedProminent)
        }
    }
}

/// 一覧の代わりに置く小さめの空状態 (枠で囲まない)。
struct InlineEmptyState: View {
    let title: String
    var message: String? = nil
    var systemImage: String = "tray"

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundStyle(Theme.accent)
            Text(title).font(.headline)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }
}

/// セクション見出し + 任意の右側アクション。
struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing()
                .font(.subheadline)
        }
        .padding(.horizontal, 4)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.title = title
        self.trailing = { EmptyView() }
    }
}

extension SectionHeader {
    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }
}

/// 折りたたみの見出し (「今日完了したもの」「過去の計画」など)。
/// DisclosureGroup だと矢印の色や位置がそろわないため自前で持つ。
struct CollapsibleHeader: View {
    let title: String
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy) { isExpanded.toggle() }
        } label: {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "開いています" : "閉じています")
    }
}
