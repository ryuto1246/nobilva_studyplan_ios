import SwiftUI

/// アプリの使い方説明ページ。静的テキスト。
struct GuideView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("AI 計画", systemImage: "sparkles").font(.headline)
                            Text("計画タブ右上の ✨ ボタンから、開始日〜終了日を指定して AI に日次計画を作らせられます。「参考書ゴール」を先に登録しておくと、期限から逆算した精度の高い計画が生成されます。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("タイマー", systemImage: "timer").font(.headline)
                            Text("計画アイテムやタスクの右にある ▶ ボタンからタイマーを起動できます。ポモドーロ / カウントダウン / ストップウォッチ / 手動記録 の 4 モード対応。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("チャット / 面談", systemImage: "bubble.left.and.bubble.right.fill").font(.headline)
                            Text("担当講師と 1:1 でチャットできます。写真を添付して質問することも可能。面談は「その他 > 面談」からキャンセル・別日時提案などができます。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 6) {
                            Label("使えない時間", systemImage: "clock.badge.exclamationmark").font(.headline)
                            Text("部活や塾など「勉強に使えない時間」を登録しておくと、AI 計画作成時に自動で除外されます。")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("使い方")
        }
    }
}
