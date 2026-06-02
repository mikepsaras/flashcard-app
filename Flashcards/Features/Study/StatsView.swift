import SwiftUI
import SwiftData

/// Cross-deck study insights — streak, activity heatmap, review totals, accuracy, and a
/// library breakdown by card maturity. A top-level sidebar destination. This wrapper holds the
/// `@Query` + stats reads and the scroll/empty-state chrome; `StatsContentView` is the pure
/// card stack (so it previews/snapshots from fixtures, and renders under `ImageRenderer`, which
/// doesn't lay out `ScrollView` content).
struct StatsView: View {
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @AppStorage(StudyStats.revisionKey) private var statsRevision = 0

    var body: some View {
        let _ = statsRevision   // re-render when stats are reset (the log isn't otherwise observed)
        let reviews = StudyStats.reviewsByDay()
        let insights = StudyInsights.make(
            decks: decks,
            reviewsByDay: reviews,
            correctByDay: StudyStats.correctByDay()
        )
        Group {
            if insights.totalCards == 0 && insights.reviewsAllTime == 0 {
                ContentUnavailableView(
                    "No Insights Yet",
                    systemImage: "chart.bar",
                    description: Text("Add some cards and study them — your streak, accuracy, and progress will show up here.")
                )
            } else {
                ScrollView {
                    StatsContentView(insights: insights, reviewsByDay: reviews)
                        .padding(Theme.Spacing.m)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.groupedBackground)
        .navigationTitle("Insights")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

/// The pure card stack — no scroll view / navigation chrome, so it renders under `ImageRenderer`.
struct StatsContentView: View {
    let insights: StudyInsights
    let reviewsByDay: [String: Int]
    var now: Date = .now

    private let learningColor = Color(hex: "#FF9500")

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            streakCard
            heatmapCard
            totalsCard
            if insights.accuracyAllTime != nil { accuracyCard }
            libraryCard
        }
    }

    // MARK: Cards

    private var streakCard: some View {
        card(nil) {
            HStack(spacing: Theme.Spacing.l) {
                bigStat("\(insights.currentStreak)", "Day streak", "flame.fill", .orange)
                bigStat("\(insights.longestStreak)", "Longest", "trophy.fill", Theme.accent)
                bigStat("\(insights.reviewsToday)", "Today", "checkmark.circle.fill", Theme.success)
            }
        }
    }

    private var heatmapCard: some View {
        card("Activity") {
            ActivityHeatmap(reviewsByDay: reviewsByDay, now: now)
        }
    }

    private var totalsCard: some View {
        card("Reviews") {
            HStack(spacing: Theme.Spacing.l) {
                miniStat("\(insights.reviewsThisWeek)", "This week")
                miniStat("\(insights.reviewsAllTime)", "All time")
                miniStat("\(insights.dailyAverage)", "Daily avg")
            }
        }
    }

    private var accuracyCard: some View {
        card("Accuracy") {
            HStack(spacing: Theme.Spacing.l) {
                miniStat(percent(insights.accuracyAllTime), "All time")
                miniStat(percent(insights.accuracyThisWeek), "This week")
                miniStat("\(insights.correctAllTime)", "Correct")
            }
        }
    }

    private var libraryCard: some View {
        card("Library") {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(spacing: Theme.Spacing.l) {
                    miniStat("\(insights.totalCards)", "Cards")
                    miniStat("\(insights.dueNow)", "Due now")
                    miniStat("\(insights.dueThisWeek)", "Due ≤ 7d")
                }
                MaturityBar(new: insights.newCount, learning: insights.learningCount, mature: insights.matureCount)
                HStack(spacing: Theme.Spacing.m) {
                    legend("New", Theme.accent, insights.newCount)
                    legend("Learning", learningColor, insights.learningCount)
                    legend("Mature", Theme.success, insights.matureCount)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Building blocks

    private func card<Content: View>(_ title: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            if let title {
                Text(title).font(Typography.headline).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: Theme.Radius.tile)
    }

    private func bigStat(_ value: String, _ label: String, _ systemImage: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: systemImage).font(.system(size: 18)).foregroundStyle(tint)
            Text(value).font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
            Text(label).font(Typography.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
            Text(label).font(Typography.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legend(_ label: String, _ color: Color, _ count: Int) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(label) \(count)").font(Typography.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }
}

/// GitHub-style contribution grid: ~26 weeks of day cells, tinted by that day's review count.
/// Drawn in plain SwiftUI (no Charts dependency, no scroll view), so it fits the deck panes and
/// renders under `ImageRenderer`.
struct ActivityHeatmap: View {
    let reviewsByDay: [String: Int]
    var now: Date = .now
    var calendar: Calendar = .current

    private let cell: CGFloat = 13
    private let gap: CGFloat = 3
    private let maxWeeks = 53

    var body: some View {
        GeometryReader { geo in
            // Fill the available width: as many weeks as fit (capped), so there's no dead space.
            let fit = Int((geo.size.width + gap) / (cell + gap))
            grid(weeks: min(max(fit, 1), maxWeeks))
        }
        .frame(height: 7 * cell + 6 * gap)
    }

    private func grid(weeks: Int) -> some View {
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
        let firstDay = calendar.date(byAdding: .day, value: -((weeks - 1) * 7), to: startOfWeek) ?? today
        return HStack(spacing: gap) {
            ForEach(Array(0..<weeks), id: \.self) { col in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        cellView(firstDay: firstDay, today: today, index: col * 7 + row)
                    }
                }
            }
        }
    }

    @ViewBuilder private func cellView(firstDay: Date, today: Date, index: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: index, to: firstDay) ?? firstDay
        let isFuture = date > today
        let count = isFuture ? 0 : (reviewsByDay[StudyStats.dayKey(date, calendar: calendar)] ?? 0)
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(isFuture ? Color.clear : color(count))
            .frame(width: cell, height: cell)
    }

    private func color(_ count: Int) -> Color {
        switch count {
        case 0:      Color.primary.opacity(0.08)
        case 1...2:  Theme.accent.opacity(0.30)
        case 3...5:  Theme.accent.opacity(0.50)
        case 6...10: Theme.accent.opacity(0.75)
        default:     Theme.accent
        }
    }
}

/// A thin stacked bar showing the New / Learning / Mature proportions of the library.
struct MaturityBar: View {
    let new: Int
    let learning: Int
    let mature: Int

    private var total: Int { max(new + learning + mature, 1) }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                segment(Theme.accent, new, geo.size.width)
                segment(Color(hex: "#FF9500"), learning, geo.size.width)
                segment(Theme.success, mature, geo.size.width)
            }
        }
        .frame(height: 10)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }

    private func segment(_ color: Color, _ count: Int, _ width: CGFloat) -> some View {
        color.frame(width: width * CGFloat(count) / CGFloat(total))
    }
}

/// The "Insights" sidebar row (mirrors `TodayRow`).
struct InsightsRow: View {
    @Environment(\.backgroundProminence) private var prominence
    private var selected: Bool { prominence == .increased }

    var body: some View {
        HStack(spacing: 12) {
            SidebarIconChip(systemName: "chart.bar.fill", color: Theme.accent, selected: selected)
            VStack(alignment: .leading, spacing: 2) {
                Text("Insights").font(Typography.headline)
                Text("Streak & progress").font(Typography.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
        }
        .padding(.vertical, 4)
    }
}
