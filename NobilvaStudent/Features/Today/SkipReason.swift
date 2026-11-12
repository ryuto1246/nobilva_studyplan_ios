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
    /// スキップの理由を選ぶダイアログ。item が入ると開き、選ぶと onSkip が呼ばれる。
    func skipReasonDialog(item: Binding<StudyItem?>, onSkip: @escaping (StudyItem, String?) -> Void) -> some View {
        confirmationDialog(
            "やらない理由を選んでください",
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            titleVisibility: .visible,
            presenting: item.wrappedValue
        ) { target in
            ForEach(SkipReason.allCases) { reason in
                Button(reason.rawValue) { onSkip(target, reason.rawValue) }
            }
            Button("理由は選ばない") { onSkip(target, nil) }
            Button("キャンセル", role: .cancel) {}
        } message: { target in
            Text("「\(target.title)」をスキップします。先生にも伝わり、次の計画を立てるときの参考になります。")
        }
    }
}
