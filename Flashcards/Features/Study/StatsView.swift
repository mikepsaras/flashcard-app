import SwiftUI
import SwiftData

/// Cross-deck study insights — streak, activity heatmap, review totals, accuracy, and a
/// library breakdown by card maturity. A top-level sidebar destination. This wrapper holds the
/// `@Query` + stats reads and the scroll/empty-state chrome; `StatsContentView` is the pure
/// dashboard (so it previews/snapshots from fixtures, and renders under `ImageRenderer`, which
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

/// The pure dashboard — a dense grid of stat tiles plus the heatmap and maturity bar. No scroll
/// view / navigation chrome, so it renders under `ImageRenderer`.
struct StatsContentView: View {
    let insights: StudyInsights
    let reviewsByDay: [String: Int]
    var now: Date = .now

    private let learningColor = Theme.learning

    private struct Stat: Identifiable {
        var id: String { label }
        let label: String
        let value: String
        let icon: String
        let tint: Color
    }

    private var stats: [Stat] {
        [
            Stat(label: "Day streak", value: "\(insights.currentStreak)", icon: "flame.fill", tint: .orange),
            Stat(label: "Longest streak", value: "\(insights.longestStreak)", icon: "trophy.fill", tint: Theme.accent),
            Stat(label: "Reviewed today", value: "\(insights.reviewsToday)", icon: "checkmark.circle.fill", tint: Theme.success),
            Stat(label: "Accuracy", value: percent(insights.accuracyAllTime), icon: "target", tint: Theme.success),
            Stat(label: "Reviews all-time", value: "\(insights.reviewsAllTime)", icon: "tray.full.fill", tint: Theme.accent),
            Stat(label: "Daily average", value: "\(insights.dailyAverage)", icon: "chart.bar.fill", tint: Theme.accent),
            Stat(label: "Cards", value: "\(insights.totalCards)", icon: "rectangle.on.rectangle.angled", tint: Theme.accent),
            Stat(label: "Due now", value: "\(insights.dueNow)", icon: "clock.fill", tint: insights.dueNow > 0 ? .orange : .secondary),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.m)],
                spacing: Theme.Spacing.m
            ) {
                ForEach(stats) { tile($0) }
            }
            heatmapCard
            maturityCard
        }
    }

    // MARK: Pieces

    private func tile(_ stat: Stat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: stat.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(stat.tint)
            Text(stat.value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(stat.label).font(Typography.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface(cornerRadius: Theme.Radius.tile)
    }

    private var heatmapCard: some View {
        card("Activity") {
            ActivityHeatmap(reviewsByDay: reviewsByDay, now: now)
        }
    }

    private var maturityCard: some View {
        card("Card maturity") {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                MaturityBar(new: insights.newCount, learning: insights.learningCount, mature: insights.matureCount)
                HStack(spacing: Theme.Spacing.l) {
                    legend("New", Theme.accent, insights.newCount)
                    legend("Learning", learningColor, insights.learningCount)
                    legend("Mature", Theme.success, insights.matureCount)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title).font(Typography.headline).foregroundStyle(.secondary)
            content()
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: Theme.Radius.tile)
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

/// GitHub-style contribution grid: weeks of day cells, tinted by that day's review count. Fills
/// the available width (as many weeks as fit, up to a year). Drawn in plain SwiftUI (no Charts
/// dependency, no scroll view), so it renders under `ImageRenderer`.
struct ActivityHeatmap: View {
    let reviewsByDay: [String: Int]
    var now: Date = .now
    var calendar: Calendar = .current

    private let cell: CGFloat = 13
    private let gap: CGFloat = 3
    private let maxWeeks = 53

    /// Scale colors to the user's own busiest day, so intensity reads meaningfully at any volume.
    private var maxCount: Int { max(reviewsByDay.values.max() ?? 0, 1) }

    var body: some View {
        GeometryReader { geo in
            let weeks = min(max(Int((geo.size.width + gap) / (cell + gap)), 1), maxWeeks)
            let today = calendar.startOfDay(for: now)
            let weekday = calendar.component(.weekday, from: today)
            let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
            let firstDay = calendar.date(byAdding: .day, value: -((weeks - 1) * 7), to: startOfWeek) ?? today
            VStack(alignment: .leading, spacing: 4) {
                monthLabels(weeks: weeks, firstDay: firstDay)
                grid(weeks: weeks, firstDay: firstDay, today: today)
                legend
            }
        }
        .frame(height: 7 * cell + 6 * gap + 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity heatmap of daily reviews over the past year")
    }

    private func grid(weeks: Int, firstDay: Date, today: Date) -> some View {
        HStack(spacing: gap) {
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
            .help(isFuture ? "" : "\(date.formatted(date: .abbreviated, time: .omitted)): \(count) review\(count == 1 ? "" : "s")")
    }

    /// Month abbreviations placed at the column where each new month begins (aligned to the grid).
    private func monthLabels(weeks: Int, firstDay: Date) -> some View {
        var labels: [(col: Int, text: String)] = []
        var lastMonth = -1
        for col in 0..<weeks {
            guard let weekStart = calendar.date(byAdding: .day, value: col * 7, to: firstDay) else { continue }
            let month = calendar.component(.month, from: weekStart)
            if month != lastMonth {
                lastMonth = month
                labels.append((col, calendar.shortMonthSymbols[month - 1]))
            }
        }
        // Drop a leading partial-month label that would collide with the next month's.
        if labels.count >= 2, labels[0].col == 0, labels[1].col < 3 { labels.removeFirst() }
        return ZStack(alignment: .topLeading) {
            ForEach(labels.indices, id: \.self) { i in
                Text(labels[i].text)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .offset(x: CGFloat(labels[i].col) * (cell + gap))
            }
        }
        .frame(height: 12, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var legend: some View {
        HStack(spacing: 4) {
            Text("Less").font(.system(size: 9)).foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(levelColor(level))
                    .frame(width: 10, height: 10)
            }
            Text("More").font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }

    private func color(_ count: Int) -> Color {
        guard count > 0 else { return levelColor(0) }
        switch Double(count) / Double(maxCount) {
        case ..<0.25: return levelColor(1)
        case ..<0.5:  return levelColor(2)
        case ..<0.75: return levelColor(3)
        default:      return levelColor(4)
        }
    }

    private func levelColor(_ level: Int) -> Color {
        switch level {
        case 1:  Theme.accent.opacity(0.28)
        case 2:  Theme.accent.opacity(0.48)
        case 3:  Theme.accent.opacity(0.72)
        case 4:  Theme.accent
        default: Color.primary.opacity(0.08)
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
                segment(Theme.learning, learning, geo.size.width)
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
