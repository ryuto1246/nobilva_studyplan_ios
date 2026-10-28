import SwiftUI

/// 計測中だけタブバーの上に出るバー (ミュージックのミニプレイヤーと同じ位置づけ)。
/// タップでタイマーを開き、右のボタンで一時停止 / 再開できる。
struct TimerAccessoryBar: View {
    @EnvironmentObject var timer: StudyTimer
    @EnvironmentObject var router: AppRouter

    var body: some View {
        HStack(spacing: 12) {
            Button {
                router.timerPresented = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: timer.isRunning ? "timer" : "pause.circle")
                        .font(.title3)
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.pulse, isActive: timer.isRunning)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(timer.snapshot.item?.title ?? "自由学習")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(status)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("計測中: \(timer.snapshot.item?.title ?? "自由学習")、\(status)")
            .accessibilityHint("タイマーを開きます")

            Button {
                timer.isRunning ? timer.pause() : timer.resume()
            } label: {
                Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(timer.reading.finished)
            .accessibilityLabel(timer.isRunning ? "一時停止" : "再開")
        }
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .frame(minHeight: 52)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.separator.opacity(0.3), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    private var status: String {
        let clock = TimerView.clock(timer.displaySeconds)
        if timer.reading.finished { return "時間になりました · 記録してください" }
        if timer.isPaused { return "一時停止中 · \(clock)" }
        switch timer.snapshot.mode {
        case .pomodoro: return "\(timer.reading.phase.label) 残り \(clock)"
        case .timer: return "残り \(clock)"
        case .stopwatch: return clock
        }
    }
}

extension View {
    /// タブのルート画面に付ける。計測中だけ下端に TimerAccessoryBar を差し込む。
    func timerAccessory() -> some View {
        modifier(TimerAccessoryModifier())
    }
}

private struct TimerAccessoryModifier: ViewModifier {
    @EnvironmentObject var timer: StudyTimer

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if timer.hasSession {
                TimerAccessoryBar()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: timer.hasSession)
    }
}
