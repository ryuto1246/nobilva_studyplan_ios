import SwiftUI

/// 表示名の最初の 1 文字を丸で囲む。iconography-lite なアバター。
struct ChatAvatar: View {
    let name: String
    var size: CGFloat = 36

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
    }

    var body: some View {
        Text(initial)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Theme.subjectColor(name))
            .clipShape(Circle())
    }
}
