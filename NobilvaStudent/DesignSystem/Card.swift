import SwiftUI

/// 汎用カード背景。iOS 26+ でも見た目は同じ (Liquid Glass 疲れないため)。
struct Card<Content: View>: View {
    let padding: CGFloat
    let content: Content

    init(padding: CGFloat = Theme.cardPadding, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.secondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
    }
}

struct SectionTitle: View {
    let title: String
    let systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.secondaryLabel)
            }
            Text(title)
                .font(.headline)
        }
        .padding(.horizontal, 4)
    }
}
