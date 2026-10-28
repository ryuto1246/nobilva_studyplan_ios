import SwiftUI
import Charts

/// 学習記録 (マイページから push)。直近 7 日の学習時間を日ごとに見せる。
struct HistoryView: View {
    @EnvironmentObject var auth: AuthStore

    @State private var stats: StudyStats?
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let stats {
                content(stats)
            } else if isLoading {
                LoadingStateView()
            } else {
                ScrollView { RetryStateView { await load() }.padding(.top, 80) }
            }
        }
        .background(Theme.groupedBackground.ignoresSafeArea())
        .navigationTitle("学習記録")
        .task { await load() }
        .refreshable { await load() }
        .errorAlert($errorMessage)
    }

    private func content(_ s: StudyStats) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    StatCard(label: "今日", value: formatMinutes(s.todayMinutes), systemImage: "sun.max")
                    StatCard(label: "直近7日", value: formatMinutes(s.totalMinutes), systemImage: "calendar")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("日ごとの学習時間").font(.headline)
                    if s.totalMinutes == 0 {
                        InlineEmptyState(
                            title: "まだ記録がありません",
                            message: "今日画面の「取り組む」からタイマーを使うと、ここに記録されます。",
                            systemImage: "chart.bar"
                        )
                    } else {
                        Chart(s.days) { d in
                            BarMark(x: .value("日付", d.label), y: .value("分", d.minutes))
                                .foregroundStyle(Theme.accent)
                                .accessibilityLabel(d.label)
                                .accessibilityValue(formatMinutes(d.minutes))
                        }
                        .chartYAxis { AxisMarks(position: .leading) }
                        .frame(height: 200)
                        Text("1日平均 \(formatMinutes(s.totalMinutes / 7))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(Theme.secondaryBackground, in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
            }
            .padding(16)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            stats = try await StudyStats.load(api: auth.api)
        } catch {
            if stats != nil, (error as? APIError)?.isCancelled != true {
                errorMessage = "最新の記録を読み込めませんでした。"
            }
        }
    }
}

/// 直近 7 日の学習時間集計。日付の区切りは JST。
struct StudyStats {
    struct Day: Identifiable {
        let id: String
        let label: String
        let minutes: Int
    }

    let days: [Day]
    var totalMinutes: Int { days.reduce(0) { $0 + $1.minutes } }
    var todayMinutes: Int { days.last?.minutes ?? 0 }

    static func load(api: APIClient) async throws -> StudyStats {
        // サーバは「今から N×24 時間」で区切るため、最も古い日が欠けないよう 1 日多く取る。
        let sessions = try await SessionsRepository(api: api).sessions(days: 8)
        return StudyStats(sessions: sessions)
    }

    init(sessions: [StudySession]) {
        var byDay: [String: Int] = [:]
        for s in sessions {
            guard let startedAt = JSTDate.parseTimestamp(s.startedAt) else { continue }
            byDay[JSTDate.iso.string(from: startedAt), default: 0] += s.durationSeconds / 60
        }
        days = (0..<7).reversed().map { offset in
            let ymd = JSTDate.todayString(offsetDays: -offset)
            let label = JSTDate.date(from: ymd).map { JSTDate.displayShort.string(from: $0) } ?? ymd
            return Day(id: ymd, label: label, minutes: byDay[ymd] ?? 0)
        }
    }
}

struct SessionsRepository {
    let api: APIClient
    func sessions(days: Int) async throws -> [StudySession] {
        try await api.get("/api/v1/student/sessions", query: ["days": "\(days)"])
    }
}
