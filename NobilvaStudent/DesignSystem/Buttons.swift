import SwiftUI

/// 画面の主操作。横幅いっぱいで、処理中はスピナーに切り替わる。
struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading = false
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ButtonLabel(title: title, systemImage: systemImage, isLoading: isLoading)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isLoading)
    }
}

/// 主操作の隣に並べる副操作。
struct SecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading = false
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isLoading: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isLoading = isLoading
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ButtonLabel(title: title, systemImage: systemImage, isLoading: isLoading)
        }
        .buttonStyle(.bordered)
        .disabled(isLoading)
    }
}

private struct ButtonLabel: View {
    let title: String
    let systemImage: String?
    let isLoading: Bool

    var body: some View {
        HStack(spacing: 6) {
            if isLoading {
                ProgressView()
            } else if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .font(.body.weight(.semibold))
        .frame(maxWidth: .infinity, minHeight: 34)
    }
}
