import SwiftUI

/// 計画を「やらない (スキップ)」にするときの理由の選択肢。
/// 選んだ文言はそのまま先生の画面に出るので、生徒が書いた言葉として自然な形にしている。
/// 理由は任意 (「理由は選ばない」でもスキップできる)。
enum SkipReason: String, CaseIterable, Identifiable {
    case noTime = "時間が足りなかった"
    case tooHard = "難しくて進められなかった"
    case otherStudy = "ほかの勉強を優先した"
    case condition = "体調がよくなかった"
    case schedule = "予定が入った"

    var id: String { rawValue }

    /// 先生に相談を送ったときに自動で付ける理由。選択肢には出さない。
    /// 先生の画面にはこの文言がそのまま出る。
    static let consultedReason = "先生に相談した"
}

extension View {
    /// スキップの理由を選ぶシート。item が入ると開き、選ぶと onSkip が呼ばれる。
    ///
    /// confirmationDialog は iOS 26 で「付けた View を指す吹き出し」になり、画面全体に
    /// 付けると矢印が関係ない場所を指すうえ、選択肢がアクセント色で読みにくい。
    /// 入口が 3 か所 (まずはこれ・長押し・計画一覧) あるので、下から出るシートにしている。
    /// onConsult を渡すと、先頭に「スキップせずに先生に相談する」を出す
    /// (「難しくて進められない」ときは、黙ってスキップするより先生に聞くほうがいいため)。
    func skipReasonDialog(item: Binding<StudyItem?>,
                          onConsult: ((StudyItem) -> Void)? = nil,
                          onSkip: @escaping (StudyItem, String?) -> Void) -> some View {
        sheet(item: item) { target in
            SkipReasonSheet(
                item: target,
                onConsult: onConsult.map { consult in
                    {
                        item.wrappedValue = nil
                        // シートが閉じきる前に次の画面 (相談シート) を出すと出ないことがあるので少し待つ。
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { consult(target) }
                    }
                },
                onSelect: { reason in
                    item.wrappedValue = nil
                    onSkip(target, reason)
                }
            )
        }
    }
}

/// 中身の高さぴったりで出すシート。medium で止めると最後の選択肢が画面の下端
/// (ホームインジケーターの上) に隠れて押しにくいため、中身を測って高さを決める。
private struct SkipReasonSheet: View {
    let item: StudyItem
    var onConsult: (() -> Void)?
    let onSelect: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var contentHeight: CGFloat = 480

    var body: some View {
        // 文字を大きくしている端末では画面に収まらないことがあるので、そのときだけスクロールさせる。
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                Text("やらない理由")
                    .font(.headline)
                HStack {
                    Button("キャンセル") { dismiss() }
                    Spacer()
                }
            }

            Text("「\(item.title)」をスキップします。先生にも伝わり、次の計画を立てるときの参考になります。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let onConsult {
                Button(action: onConsult) {
                    Label("スキップせずに先生に相談する", systemImage: "bubble.left")
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .padding(.horizontal, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
                .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            }

            VStack(spacing: 0) {
                ForEach(Array(SkipReason.allCases.enumerated()), id: \.element) { i, reason in
                    row(reason.rawValue) { onSelect(reason.rawValue) }
                    if i != SkipReason.allCases.count - 1 { Divider().padding(.leading, 16) }
                }
            }
            .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))

            Button { onSelect(nil) } label: {
                Text("理由は選ばずにスキップする")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    private func row(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
