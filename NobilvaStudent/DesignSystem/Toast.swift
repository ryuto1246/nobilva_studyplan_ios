import SwiftUI
import UIKit

/// 操作が終わったことを短く知らせるトースト。アプリ全体で 1 つ。
/// 「完了にしました」「保存しました」など、画面遷移を伴わない操作の結果に使う。
/// 取り消せる操作には「元に戻す」を付ける。
@MainActor
final class ToastCenter: ObservableObject {
    struct Toast: Identifiable {
        let id = UUID()
        let message: String
        let systemImage: String
        let tint: Color
        let actionTitle: String?
        let action: (() -> Void)?
    }

    @Published private(set) var current: Toast?
    private var hideTask: Task<Void, Never>?

    enum Feel { case success, neutral, warning, error }

    func show(_ message: String,
              systemImage: String = "checkmark.circle.fill",
              tint: Color = .green,
              feel: Feel = .success,
              actionTitle: String? = nil,
              action: (() -> Void)? = nil) {
        let toast = Toast(message: message, systemImage: systemImage, tint: tint,
                          actionTitle: actionTitle, action: action)
        current = toast
        switch feel {
        case .success: Haptics.success()
        case .neutral: Haptics.tap()
        case .warning: Haptics.warning()
        case .error: Haptics.error()
        }
        UIAccessibility.post(notification: .announcement, argument: message)
        hideTask?.cancel()
        // 取り消しボタン付きは押す時間を少し長めに残す。
        let seconds: UInt64 = action == nil ? 3 : 5
        hideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss(toast.id)
        }
    }

    /// 失敗の知らせ (アラートを出すほどではないもの)。
    func showError(_ message: String) {
        show(message, systemImage: "exclamationmark.circle.fill", tint: .red, feel: .error)
    }

    func dismiss(_ id: UUID? = nil) {
        if id == nil || current?.id == id { current = nil }
    }
}

private struct ToastView: View {
    let toast: ToastCenter.Toast
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.systemImage)
                .foregroundStyle(toast.tint)
                .font(.body.weight(.semibold))
            Text(toast.message)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
            if let title = toast.actionTitle {
                Spacer(minLength: 8)
                Button(title, action: onAction)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, toast.actionTitle == nil ? 16 : 10)
        .padding(.vertical, toast.actionTitle == nil ? 12 : 2)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// 画面上部、ナビゲーションバーのボタンより下にトーストを重ねる。
    /// (下部は iOS 26 のタブバーの層に隠れて見えなかった。最上部はナビバーのボタンに重なる)
    func toastHost(_ center: ToastCenter, topInset: CGFloat = 56) -> some View {
        overlay(alignment: .top) {
            if let toast = center.current {
                ToastView(toast: toast) {
                    toast.action?()
                    center.dismiss(toast.id)
                }
                .padding(.top, topInset)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { center.dismiss(toast.id) }
                .id(toast.id)
            }
        }
        .animation(.snappy, value: center.current?.id)
    }
}
