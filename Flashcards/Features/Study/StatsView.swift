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
            correctByDay: StudyStats.correctByDay(),
            matureByDay: StudyStats.matureReviewsByDay(),
            matureCorrectByDay: StudyStats.matureCorrectByDay()
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
        /// Week-over-week change, shown as a small ▲/▼ badge when non-nil and non-zero.
        var delta: Int? = nil
    }

    private var maturePercent: String {
        insights.totalCards > 0 ? "\(insights.matureCount * 100 / insights.totalCards)%" : "—"
    }

    private var stats: [Stat] {
        [
            Stat(label: "Day streak", value: "\(insights.currentStreak)", icon: "flame.fill", tint: .orange),
            Stat(label: "Longest streak", value: "\(insights.longestStreak)", icon: "trophy.fill", tint: Theme.accent),
            Stat(label: "This week", value: "\(insights.reviewsThisWeek)", icon: "calendar",
                 tint: Theme.accent, delta: insights.reviewsThisWeek - insights.reviewsLastWeek),
            Stat(label: "Reviewed today", value: "\(insights.reviewsToday)", icon: "checkmark.circle.fill", tint: Theme.success),
            Stat(label: "Accuracy", value: percent(insights.accuracyAllTime), icon: "target", tint: Theme.accent),
            Stat(label: "Mature", value: maturePercent, icon: "checkmark.seal.fill", tint: Theme.success),
            Stat(label: "Due now", value: "\(insights.dueNow)", icon: "clock.fill", tint: insights.dueNow > 0 ? .orange : .secondary),
            Stat(label: "Due in 7 days", value: "\(insights.dueThisWeek)", icon: "calendar.badge.clock",
                 tint: insights.dueThisWeek > 0 ? .orange : .secondary),
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
            if insights.predictedRetention != nil || insights.trueRetention != nil { retentionCard }
            forecastCard
            heatmapCard
            if !insights.perDeck.isEmpty { perDeckCard }
            if !insights.sections.isEmpty { bySectionCard }
            maturityCard
        }
        .frame(maxWidth: 940)          // keep the dashboard readable instead of stretching edge-to-edge
        .frame(maxWidth: .infinity)    // ...and centered in wide / fullscreen windows
    }

    // MARK: Tiles

    private func tile(_ stat: Stat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: stat.icon).font(.system(size: 15, weight: .semibold)).foregroundStyle(stat.tint)
            Text(stat.value)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 4) {
                Text(stat.label).font(Typography.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                if let delta = stat.delta, delta != 0 { trendBadge(delta) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .cardSurface(cornerRadius: Theme.Radius.tile)
    }

    /// A ▲/▼ change indicator vs. the previous week.
    private func trendBadge(_ delta: Int) -> some View {
        let up = delta > 0
        return HStack(spacing: 1) {
            Image(systemName: up ? "arrow.up" : "arrow.down").font(.system(size: 8, weight: .bold))
            Text("\(abs(delta))").font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
        }
        .foregroundStyle(up ? Theme.success : Theme.danger)
        .accessibilityLabel("\(up ? "up" : "down") \(abs(delta)) versus last week")
    }

    // MARK: Cards

    private var forecastCard: some View {
        card("Due forecast", subtitle: forecastSubtitle) {
            DueForecastChart(forecast: insights.dueForecast, now: now)
        }
    }

    private var forecastSubtitle: String {
        insights.dueThisWeek > 0
            ? "\(insights.dueThisWeek) review\(insights.dueThisWeek == 1 ? "" : "s") due in the next 7 days"
            : "Nothing due in the next 7 days"
    }

    /// Predicted recall *now* (estimated from each card's schedule) beside measured *mature*
    /// retention (Anki's "true retention"). They answer different questions — "how much would I
    /// recall right now" vs. "when a graduated card comes due, how often do I still get it" — so
    /// they sit together, clearly labeled, rather than being mistaken for the Accuracy tile.
    private var retentionCard: some View {
        card("Memory retention") {
            HStack(alignment: .top, spacing: Theme.Spacing.l) {
                retentionStat(
                    percent(insights.predictedRetention), "Predicted recall now",
                    insights.scheduledUnits > 0
                        ? "across \(insights.scheduledUnits) scheduled card\(insights.scheduledUnits == 1 ? "" : "s")"
                        : "no cards scheduled yet",
                    insights.predictedRetention)
                Divider().frame(height: 48)
                retentionStat(
                    percent(insights.trueRetention), "Mature retention",
                    insights.matureReviewCount > 0
                        ? "\(insights.matureCorrectCount) / \(insights.matureReviewCount) mature reviews correct"
                        : "study mature cards to see this",
                    insights.trueRetention)
            }
        }
    }

    private func retentionStat(_ value: String, _ label: String, _ detail: String, _ source: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit().foregroundStyle(retentionTint(source))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(Typography.caption).foregroundStyle(.primary)
            Text(detail).font(.system(size: 11, design: .rounded)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value). \(detail).")
    }

    /// Green when retention is strong, amber when it's slipping — a quick read on memory health.
    /// Unmeasured (`nil`) is neutral grey so an empty mature stat doesn't look alarming.
    private func retentionTint(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        switch value {
        case 0.9...:    return Theme.success
        case 0.8..<0.9: return Theme.accent
        default:        return .orange
        }
    }

    private var heatmapCard: some View {
        card("Activity") { ActivityHeatmap(reviewsByDay: reviewsByDay, now: now) }
    }

    private var perDeckCard: some View {
        card("By deck") {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(sortedDecks) { deckRow($0) }
            }
        }
    }

    /// Most actionable first: most due, then largest.
    private var sortedDecks: [StudyInsights.DeckStat] {
        insights.perDeck.sorted { ($0.due, $0.totalCards) > ($1.due, $1.totalCards) }
    }

    private func deckRow(_ deck: StudyInsights.DeckStat) -> some View {
        let maturePct = deck.totalCards > 0 ? deck.matureCount * 100 / deck.totalCards : 0
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(hex: deck.colorHex)).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(deck.name).font(Typography.body).lineLimit(1)
                    Spacer(minLength: 4)
                    if deck.due > 0 {
                        Text("\(deck.due) due")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.orange.opacity(Theme.Opacity.fillSubtle), in: Capsule())
                    }
                    Text("\(deck.totalCards)").font(Typography.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: 8) {
                    MaturityBar(new: deck.newCount, learning: deck.learningCount, mature: deck.matureCount)
                        .frame(height: 6)
                    Text("\(maturePct)%")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(deck.name): \(deck.totalCards) cards, \(deck.due) due, \(maturePct) percent mature")
    }

    private var bySectionCard: some View {
        card("By section") {
            VStack(spacing: Theme.Spacing.s) {
                ForEach(sortedSections) { sectionRow($0) }
            }
        }
    }

    /// Most actionable first: most due, then largest.
    private var sortedSections: [StudyInsights.SectionStat] {
        insights.sections.sorted { ($0.due, $0.totalCards) > ($1.due, $1.totalCards) }
    }

    private func sectionRow(_ section: StudyInsights.SectionStat) -> some View {
        let maturePct = section.totalCards > 0 ? section.matureCount * 100 / section.totalCards : 0
        let label = section.section.isEmpty ? "\(section.deckName) · No section" : "\(section.deckName) · \(section.section)"
        return HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(hex: section.colorHex)).frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(label).font(Typography.body).lineLimit(1)
                    Spacer(minLength: 4)
                    if section.due > 0 {
                        Text("\(section.due) due")
                            .font(.system(.caption2, design: .rounded, weight: .bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.orange.opacity(Theme.Opacity.fillSubtle), in: Capsule())
                    }
                    Text("\(section.totalCards)").font(Typography.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: 8) {
                    MaturityBar(new: section.newCount, learning: section.learningCount, mature: section.matureCount)
                        .frame(height: 6)
                    Text("\(maturePct)%")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary).monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(section.totalCards) cards, \(section.due) due, \(maturePct) percent mature")
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

    private func card<Content: View>(_ title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.headline).foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle).font(Typography.caption).foregroundStyle(.secondary)
                }
            }
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

/// A hand-drawn bar chart of reviews coming due over the next two weeks (overdue folds into the
/// first bar, "Now"). Plain SwiftUI — no Charts dependency — so it renders under `ImageRenderer`.
struct DueForecastChart: View {
    let forecast: [Int]
    var now: Date = .now
    var calendar: Calendar = .current

    private var maxCount: Int { max(forecast.max() ?? 0, 1) }

    var body: some View {
        GeometryReader { geo in
            let n = max(forecast.count, 1)
            let spacing: CGFloat = 5
            let barWidth = max((geo.size.width - spacing * CGFloat(n - 1)) / CGFloat(n), 1)
            let areaHeight = geo.size.height - 28   // room for the value + day labels
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(forecast.indices, id: \.self) { i in
                    column(i, width: barWidth, areaHeight: areaHeight)
                }
            }
        }
        .frame(height: 126)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private func column(_ i: Int, width: CGFloat, areaHeight: CGFloat) -> some View {
        let count = forecast[i]
        let height = count > 0 ? max(areaHeight * CGFloat(count) / CGFloat(maxCount), 4) : 0
        let isToday = i == 0
        return VStack(spacing: 3) {
            Spacer(minLength: 0)
            Text(count > 0 ? "\(count)" : " ")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary).lineLimit(1)
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isToday ? Color.orange : Theme.accent.opacity(0.55))
                .frame(width: width, height: height)
            Text(label(i))
                .font(.system(size: 8, weight: isToday ? .bold : .regular))
                .foregroundStyle(isToday ? .primary : .secondary)
                .lineLimit(1)
        }
    }

    private func label(_ i: Int) -> String {
        guard i > 0 else { return "Now" }
        let date = calendar.date(byAdding: .day, value: i, to: now) ?? now
        let weekday = calendar.component(.weekday, from: date)
        return String(calendar.veryShortWeekdaySymbols[weekday - 1])
    }

    private var summary: String {
        let total = forecast.reduce(0, +)
        return "Due forecast: \(total) review\(total == 1 ? "" : "s") over the next \(forecast.count) days."
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

    #if os(macOS)
    /// One reused formatter for the per-day tooltips. `Date.formatted(...)` builds a fresh format
    /// style on every call, which adds up across the ~371 cells that re-render together; a shared
    /// `DateFormatter` is far cheaper and is thread-safe for formatting (macOS 10.9+). iOS skips the
    /// tooltip entirely (`.help` doesn't surface on touch), so this is macOS-only.
    nonisolated(unsafe) private static let tooltipDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
    #endif

    var body: some View {
        GeometryReader { geo in
            let weeks = min(max(Int((geo.size.width + gap) / (cell + gap)), 1), maxWeeks)
            let today = calendar.startOfDay(for: now)
            let weekday = calendar.component(.weekday, from: today)
            let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: today) ?? today
            let firstDay = calendar.date(byAdding: .day, value: -((weeks - 1) * 7), to: startOfWeek) ?? today
            // Scale colors to the user's busiest day. Computed once per render and threaded down —
            // not recomputed inside `color(_:)` for each of the ~371 cells.
            let maxCount = max(reviewsByDay.values.max() ?? 0, 1)
            VStack(alignment: .leading, spacing: 4) {
                monthLabels(weeks: weeks, firstDay: firstDay)
                grid(weeks: weeks, firstDay: firstDay, today: today, maxCount: maxCount)
                legend
            }
        }
        .frame(height: 7 * cell + 6 * gap + 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity heatmap of daily reviews over the past year")
    }

    private func grid(weeks: Int, firstDay: Date, today: Date, maxCount: Int) -> some View {
        HStack(spacing: gap) {
            ForEach(Array(0..<weeks), id: \.self) { col in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        cellView(firstDay: firstDay, today: today, index: col * 7 + row, maxCount: maxCount)
                    }
                }
            }
        }
    }

    @ViewBuilder private func cellView(firstDay: Date, today: Date, index: Int, maxCount: Int) -> some View {
        let date = calendar.date(byAdding: .day, value: index, to: firstDay) ?? firstDay
        let isFuture = date > today
        let count = isFuture ? 0 : (reviewsByDay[StudyStats.dayKey(date, calendar: calendar)] ?? 0)
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(isFuture ? Color.clear : color(count, max: maxCount))
            .frame(width: cell, height: cell)
            #if os(macOS)
            .help(isFuture ? "" : "\(Self.tooltipDate.string(from: date)): \(count) review\(count == 1 ? "" : "s")")
            #endif
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

    private func color(_ count: Int, max maxCount: Int) -> Color {
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
