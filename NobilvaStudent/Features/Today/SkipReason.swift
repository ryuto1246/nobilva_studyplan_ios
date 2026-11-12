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
}

extension View {
    /// スキップの理由を選ぶシート。item が入ると開き、選ぶと onSkip が呼ばれる。
    ///
    /// confirmationDialog は iOS 26 で「付けた View を指す吹き出し」になり、画面全体に
    /// 付けると矢印が関係ない場所を指すうえ、選択肢がアクセント色で読みにくい。
    /// 入口が 3 か所 (まずはこれ・長押し・計画一覧) あるので、下から出るシートにしている。
    func skipReasonDialog(item: Binding<StudyItem?>, onSkip: @escaping (StudyItem, String?) -> Void) -> some View {
        sheet(item: item) { target in
            SkipReasonSheet(item: target) { reason in
                item.wrappedValue = nil
                onSkip(target, reason)
            }
        }
    }
}

private struct SkipReasonSheet: View {
    let item: StudyItem
    let onSelect: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(SkipReason.allCases) { reason in
                        row(reason.rawValue) { onSelect(reason.rawValue) }
                    }
                } header: {
                    Text("「\(item.title)」をスキップします。先生にも伝わり、次の計画を立てるときの参考になります。")
                        .font(.footnote)
                        .textCase(nil)
                }
                Section {
                    row("理由は選ばない", isSecondary: true) { onSelect(nil) }
                }
            }
            .navigationTitle("やらない理由")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ title: String, isSecondary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(isSecondary ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
    }
}
