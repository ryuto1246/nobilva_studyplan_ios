import SwiftUI
import UIKit

enum Theme {
    static let accent = Color.accentColor

    static let groupedBackground = Color(UIColor.systemGroupedBackground)
    static let secondaryBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let separator = Color(UIColor.separator)
    static let secondaryLabel = Color(UIColor.secondaryLabel)
    static let tertiaryLabel = Color(UIColor.tertiaryLabel)

    static let cardCorner: CGFloat = 16
    static let cardPadding: CGFloat = 16
    static let rowVerticalSpacing: CGFloat = 12

    /// 科目名から安定した色を導く (ハッシュベース)。
    /// 同じ科目は常に同じ色になる。
    static func subjectColor(_ subject: String) -> Color {
        let palette: [Color] = [
            .init(red: 0.31, green: 0.63, blue: 0.95),
            .init(red: 0.94, green: 0.55, blue: 0.35),
            .init(red: 0.45, green: 0.78, blue: 0.55),
            .init(red: 0.85, green: 0.43, blue: 0.68),
            .init(red: 0.62, green: 0.51, blue: 0.90),
            .init(red: 0.95, green: 0.75, blue: 0.30),
            .init(red: 0.40, green: 0.72, blue: 0.78)
        ]
        var hash = 5381
        for scalar in subject.unicodeScalars {
            hash = ((hash << 5) &+ hash) &+ Int(scalar.value)
        }
        return palette[abs(hash) % palette.count]
    }
}
