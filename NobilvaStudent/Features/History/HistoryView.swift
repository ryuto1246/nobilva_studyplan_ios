import SwiftUI
import Charts

struct HistoryView: View {
    @EnvironmentObject var auth: AuthStore

    struct DailyStat: Identifiable {
        let id: String
        let date: Date
        let minutes: Int
        let label: String
    }

    @State private var stats: [DailyStat] = []
    @State private var totalMinutes: Int = 0
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryRow
                    chartCard
                    if let msg = errorMessage {
                        Text(msg).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .background(Theme.groupedBackground.ignoresSafeArea())
            .navigationTitle("履歴")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 10) {
            StatCard(label: "過去 7 日合計", value: "\(totalMinutes) 分", systemImage: "clock", tint: .accentColor)
            StatCard(label: "1 日平均", value: "\(totalMinutes / 7) 分", systemImage: "chart.bar.fill", tint: .green)
        }
    }

    private var chartCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("過去 7 日の学習時間 (分)").font(.headline)
                if stats.isEmpty {
                    Text(isLoading ? "読み込み中…" : "データがありません")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.vertical, 30).frame(maxWidth: .infinity)
                } else {
                    Chart(stats) { s in
                        BarMark(x: .value("日付", s.label), y: .value("分", s.minutes))
                            .foregroundStyle(Theme.accent)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .frame(height: 180)
                }
            }
        }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        errorMessage = nil
        do {
            let sessions = try await SessionsRepository(api: auth.api).sessions(days: 7)
            stats = aggregate(sessions: sessions)
            totalMinutes = stats.reduce(0) { $0 + $1.minutes }
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = "読み込みに失敗しました"
        }
    }

    private func aggregate(sessions: [StudySession]) -> [DailyStat] {
        let cal = JSTDate.calendar
        var byDay: [String: Int] = [:]
        for s in sessions {
            guard let startedAt = JSTDate.parseTimestamp(s.startedAt) else { continue }
            let day = JSTDate.iso.string(from: startedAt)
            byDay[day, default: 0] += (s.durationSeconds / 60)
        }
        let today = cal.startOfDay(for: Date())
        return (0..<7).reversed().map { offset in
            let d = cal.date(byAdding: .day, value: -offset, to: today) ?? today
            let ymd = JSTDate.iso.string(from: d)
            let minutes = byDay[ymd] ?? 0
            let label = JSTDate.displayShort.string(from: d)
            return DailyStat(id: ymd, date: d, minutes: minutes, label: label)
        }
    }
}

struct SessionsRepository {
    let api: APIClient
    func sessions(days: Int) async throws -> [StudySession] {
        try await api.get("/api/v1/student/sessions", query: ["days": "\(days)"])
    }
}
