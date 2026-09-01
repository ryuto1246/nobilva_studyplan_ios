import SwiftUI

struct MeetingListView: View {
    @EnvironmentObject var auth: AuthStore

    @State private var meetings: [Meeting] = []
    @State private var includePast = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Toggle("過去の面談も表示", isOn: $includePast)
                    .onChange(of: includePast) { _, _ in Task { await load() } }
                if let groups = upcomingByMonth, !groups.isEmpty {
                    ForEach(groups, id: \.month) { g in
                        Section("これから ・ \(g.monthLabel)") {
                            ForEach(g.items) { row($0) }
                        }
                    }
                }
                if let past = past, !past.isEmpty {
                    Section("過去") {
                        ForEach(past) { row($0) }
                    }
                }
                if meetings.isEmpty && !isLoading {
                    ContentUnavailableView("面談はありません", systemImage: "calendar")
                }
            }
            .navigationTitle("面談")
            .task {
                if meetings.isEmpty, let cached = MeetingsRepository.cachedList(includePast: includePast) {
                    meetings = cached
                }
                await load()
            }
            .refreshable { await load() }
            .overlay { if isLoading && meetings.isEmpty { ProgressView() } }
            .errorAlert($errorMessage)
        }
    }

    private var upcoming: [Meeting]? {
        let x = meetings.filter { !$0.isPast && $0.status != .cancelled }
        return x.isEmpty ? nil : x.sorted { $0.scheduledStartAt < $1.scheduledStartAt }
    }
    private var past: [Meeting]? {
        let x = meetings.filter { $0.isPast || $0.status == .cancelled }
        return x.isEmpty ? nil : x.sorted { $0.scheduledStartAt > $1.scheduledStartAt }
    }

    /// (yyyy-MM ラベル, 該当月の面談) の配列を月順に。
    private struct MonthGroup { let month: String; let monthLabel: String; let items: [Meeting] }
    private var upcomingByMonth: [MonthGroup]? {
        guard let upcoming, !upcoming.isEmpty else { return nil }
        let cal = JSTDate.calendar
        var buckets: [(key: String, label: String, items: [Meeting])] = []
        for m in upcoming {
            guard let start = JSTDate.parseTimestamp(m.scheduledStartAt) else { continue }
            let comps = cal.dateComponents([.year, .month], from: start)
            let key = String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
            let label = "\(comps.year ?? 0)年\(comps.month ?? 0)月"
            if let idx = buckets.firstIndex(where: { $0.key == key }) {
                buckets[idx].items.append(m)
            } else {
                buckets.append((key, label, [m]))
            }
        }
        return buckets.map { MonthGroup(month: $0.key, monthLabel: $0.label, items: $0.items) }
    }

    private func row(_ m: Meeting) -> some View {
        NavigationLink {
            MeetingDetailView(meetingId: m.id).environmentObject(auth)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(m.title).font(.subheadline).bold()
                    Spacer()
                    Text(m.displayStatus.label)
                        .font(.caption2).padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2)).clipShape(Capsule())
                }
                if let start = JSTDate.parseTimestamp(m.scheduledStartAt) {
                    Text(JSTDate.displayLong.string(from: start) + " " + JSTDate.time.string(from: start))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let tName = m.teacher?.displayName {
                    Text(tName).font(.caption).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func load() async {
        isLoading = true; defer { isLoading = false }
        do {
            meetings = try await MeetingsRepository(api: auth.api).list(includePast: includePast)
        } catch let e as APIError {
            if meetings.isEmpty { errorMessage = e.errorDescription }
        } catch {
            if meetings.isEmpty { errorMessage = "読み込みに失敗しました" }
        }
    }
}
