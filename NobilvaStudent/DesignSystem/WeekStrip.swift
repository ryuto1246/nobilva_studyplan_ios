import SwiftUI

/// 日付を横に並べた帯 (カレンダーアプリの週表示に近いもの)。
/// 各日に曜日・日付と、その日の進み具合 (計画なし / 未完了 / 全部完了) を小さく出す。
struct WeekStrip: View {
    let days: [PlanDay]
    let selected: String?
    /// true なら横スクロールせず、全日を幅いっぱいに等分して並べる (1 週間分の表示用)。
    var fillsWidth = false
    let onSelect: (String) -> Void

    private let today = JSTDate.todayString()

    var body: some View {
        if fillsWidth {
            HStack(spacing: 6) {
                ForEach(days) { day in cell(day).frame(maxWidth: .infinity) }
            }
        } else {
            scrolling
        }
    }

    private func cell(_ day: PlanDay) -> some View {
        DayCell(day: day, isToday: day.date == today, isSelected: day.date == selected, flexible: fillsWidth)
            .onTapGesture {
                Haptics.selection()
                onSelect(day.date)
            }
    }

    private var scrolling: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(days) { day in cell(day).id(day.date) }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
            .onAppear {
                if let selected { proxy.scrollTo(selected, anchor: .center) }
            }
            .onChange(of: selected) { _, new in
                if let new { withAnimation { proxy.scrollTo(new, anchor: .center) } }
            }
        }
    }
}

private struct DayCell: View {
    let day: PlanDay
    let isToday: Bool
    let isSelected: Bool
    var flexible = false

    private var date: Date? { JSTDate.date(from: day.date) }

    var body: some View {
        VStack(spacing: 4) {
            Text(date.map { Self.weekday.string(from: $0) } ?? "")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : (isToday ? Theme.accent : .secondary))
            Text(date.map { Self.dayNumber.string(from: $0) } ?? "")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(isSelected ? .white : .primary)
            status
                .frame(height: 8)
        }
        .frame(width: flexible ? nil : 48, height: 72)
        .frame(maxWidth: flexible ? .infinity : nil)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Theme.accent : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isToday && !isSelected ? Theme.accent.opacity(0.6) : .clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(JSTDate.monthDay(day.date))\(isToday ? "、今日" : "")")
        .accessibilityValue(day.items.isEmpty ? "計画なし" : "\(day.items.count)件中\(day.doneCount)件完了")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    /// 計画なし: 何も出さない / 全部完了: チェック / それ以外: 件数ぶんの点 (最大 4)。
    @ViewBuilder
    private var status: some View {
        let tint: Color = isSelected ? .white : Theme.accent
        if day.items.isEmpty {
            Color.clear
        } else if day.isAllDone {
            Image(systemName: "checkmark")
                .font(.system(size: 8, weight: .heavy))
                .foregroundStyle(tint)
        } else {
            HStack(spacing: 3) {
                ForEach(0..<min(day.items.count, 4), id: \.self) { i in
                    Circle()
                        .fill(i < day.doneCount ? tint.opacity(0.35) : tint)
                        .frame(width: 5, height: 5)
                }
            }
        }
    }

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.calendar = JSTDate.calendar; f.timeZone = JSTDate.timeZone
        f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "E"
        return f
    }()

    private static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.calendar = JSTDate.calendar; f.timeZone = JSTDate.timeZone
        f.locale = Locale(identifier: "ja_JP"); f.dateFormat = "d"
        return f
    }()
}
