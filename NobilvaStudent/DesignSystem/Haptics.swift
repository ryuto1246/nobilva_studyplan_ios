import UIKit

/// 触覚フィードバックの唯一の入口。画面ごとに Generator を直接作らない。
///
/// 使い分け:
///  - success: 操作が完了した (完了にした・記録した・保存した・送った)
///  - error: 操作が失敗した (エラー表示と同時)
///  - warning: 取り消せない操作の確認を出す / 破棄した
///  - tap: 状態が切り替わる軽い操作 (一時停止・再開・送信の開始・折りたたみ)
///  - impact: 計測の開始やフェーズの切り替わりなど、はっきり知らせたい節目
///  - selection: 選択肢を切り替えた (モード・対象の選択)
///
/// トーストとエラーアラートは自動で鳴らすので、それらを出す箇所では呼ばないこと (二重になる)。
@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func tap() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func impact() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
}
