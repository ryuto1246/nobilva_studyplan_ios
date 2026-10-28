import SwiftUI

/// アプリの使い方 (マイページ > 使い方)。今の画面構成に合わせた静的な説明。
struct GuideView: View {
    private struct Topic: Identifiable {
        let id = UUID()
        let title: String
        let systemImage: String
        let body: String
    }

    private let topics: [Topic] = [
        Topic(title: "今日やること", systemImage: "checklist",
              body: "「今日」タブを開くと、いちばん先に取り組むことが「まずはこれ」として大きく表示されます。終わったら「完了」を押すか、丸いチェックをタップします。期限を過ぎたタスクも同じ並びに入ります。"),
        Topic(title: "タイマーで記録する", systemImage: "timer",
              body: "「取り組む」を押すとタイマーが開きます。閉じても計測は続き、画面下のバーからいつでも戻れます。終わったら「記録する」を押すと、学習時間が記録され、その計画は完了になります。"),
        Topic(title: "先生に相談する", systemImage: "bubble.left",
              body: "やることを長押しするか、「まずはこれ」の「先生に相談する」から、その内容について先生にチャットで相談できます。"),
        Topic(title: "面談", systemImage: "person.2",
              body: "次の面談は「今日」タブに表示されます。日程の変更を希望するときや、過去の面談を見るときは「マイページ > 面談」から開きます。"),
        Topic(title: "使えない時間", systemImage: "clock.badge.xmark",
              body: "部活や塾など勉強できない時間を「マイページ > 使えない時間」に登録しておくと、先生が計画を立てるときに避けてくれます。"),
    ]

    var body: some View {
        List(topics) { t in
            VStack(alignment: .leading, spacing: 6) {
                Label(t.title, systemImage: t.systemImage)
                    .font(.headline)
                Text(t.body)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("使い方")
        .navigationBarTitleDisplayMode(.inline)
    }
}
