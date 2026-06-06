import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Cross-deck study insights — streak, activity heatmap, review totals, accuracy, and a
/// library breakdown by card maturity. A top-level sidebar destination. This wrapper holds the
/// `@Query` + stats reads and the scroll/empty-state chrome; `StatsContentView` is the pure
/// dashboard (so it previews/snapshots from fixtures, and renders under `ImageRenderer`, which
/// doesn't lay out `ScrollView` content).
struct StatsView: View {
    @Query(sort: \Deck.createdAt) private var decks: [Deck]
    @AppStorage(StudyStats.revisionKey) private var statsRevision = 0
    @State private var showingExporter = false
    @State private var exportText = ""

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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { exportCSV() } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                    .disabled(insights.totalCards == 0 && insights.reviewsAllTime == 0)
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: CSVDocument(text: exportText),
            contentType: .commaSeparatedText,
            defaultFilename: "Flashcards Insights"
        ) { _ in }
    }

    /// Builds the Insights CSV (summary + per-deck/category/section tables + daily log) and opens the
    /// save panel. Recomputed fresh from the current logs on tap.
    private func exportCSV() {
        let reviews = StudyStats.reviewsByDay()
        let insights = StudyInsights.make(
            decks: decks, reviewsByDay: reviews, correctByDay: StudyStats.correctByDay(),
            matureByDay: StudyStats.matureReviewsByDay(), matureCorrectByDay: StudyStats.matureCorrectByDay()
        )
        exportText = StatsCSV.export(insights: insights, reviewsByDay: reviews, correctByDay: StudyStats.correctByDay())
        showingExporter = true
    }
}

/// The pure dashboard — a dense grid of stat tiles plus the heatmap and maturity bar. No scroll
/// view / navigation chrome, so it renders under `ImageRenderer`.
struct StatsContentView: View {
    let insights: StudyInsights
    let reviewsByDay: [String: Int]
    var now: Date = .now
    var calendar: Calendar = .current

    /// 0 ⇒ the trailing-12-months view ("Past year"); otherwise a calendar year (e.g. 2025) to show.
    @AppStorage(DefaultsKey.heatmapYear) private var heatmapYear = 0

    @AppStorage(DefaultsKey.retentionGraph) private var retentionGraphRaw = RetentionGraph.spread.rawValue
    private var retentionGraph: RetentionGraph { RetentionGraph(rawValue: retentionGraphRaw) ?? .spread }

    /// The hero recall ring's look-ahead (now / 1wk / 1mo) — tap the ring to cycle.
    @AppStorage(DefaultsKey.insightsRecallHorizon) private var recallHorizonRaw = RetentionHorizon.now.rawValue
    private var recallHorizon: RetentionHorizon { RetentionHorizon(rawValue: recallHorizonRaw) ?? .now }

    /// Which "Your library" breakdown is shown — tap the chip to cycle the available groupings.
    @AppStorage(DefaultsKey.insightsLibraryGrouping) private var libraryGroupingRaw = LibraryGrouping.deck.rawValue

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

    /// Four headline KPIs (down from eight); the streak / due / recall story lives in the hero, and
    /// the rest is the sections below.
    private var overviewStats: [Stat] {
        [
            Stat(label: "Reviewed today", value: "\(insights.reviewsToday)", icon: "checkmark.circle.fill", tint: Theme.success),
            Stat(label: "This week", value: "\(insights.reviewsThisWeek)", icon: "calendar",
                 tint: Theme.accent, delta: insights.reviewsThisWeek - insights.reviewsLastWeek),
            Stat(label: "Accuracy", value: percent(insights.accuracyAllTime), icon: "target", tint: Theme.accent),
            Stat(label: "Mature", value: maturePercent, icon: "checkmark.seal.fill", tint: Theme.success),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            hero
            // Four equal, flexible columns so the tiles always fill the width — no trailing dead
            // space (adaptive columns left empty slots at wide sizes).
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.m), count: 4),
                spacing: Theme.Spacing.m
            ) {
                ForEach(overviewStats) { tile($0) }
            }
            heatmapCard
            memoryCard
            libraryCard
        }
        .frame(maxWidth: 940)          // keep the dashboard readable instead of stretching edge-to-edge
        .frame(maxWidth: .infinity)    // ...and centered in wide / fullscreen windows
    }

    // MARK: Hero

    /// The narrative beat on top: streak headline, a one-line summary, and the predicted-recall ring.
    private var hero: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: heroIcon).font(.system(size: 28)).foregroundStyle(heroTint)
                    Text(heroHeadline).font(.system(size: 30, weight: .bold, design: .rounded))
                }
                Text(heroSummary).font(Typography.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            RetentionRing(recall: insights.predictedRecallByHorizon[recallHorizon.days], phrase: recallHorizon.phrase) {
                recallHorizonRaw = recallHorizon.next.rawValue
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.05)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(heroHeadline). \(heroSummary).")
    }

    private var heroHeadline: String {
        insights.currentStreak > 0 ? "\(insights.currentStreak)-day streak" : "Your progress"
    }
    private var heroIcon: String { insights.currentStreak > 0 ? "flame.fill" : "chart.bar.fill" }
    private var heroTint: Color { insights.currentStreak > 0 ? .orange : Theme.accent }
    private var heroSummary: String {
        var parts = ["\(insights.dueNow) due today"]
        if insights.reviewsAllTime > 0 { parts.append("\(insights.reviewsAllTime) reviewed all-time") }
        return parts.joined(separator: " · ")
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

    /// Predicted recall *now* and measured *mature* retention as a legend under a graph that cycles
    /// Spread → Trend → Curve on tap (a chip names the current one) — no segmented control / tabs.
    /// Calibration of predicted vs. actual recall from the review log (E6); nil until enough reviews.
    /// Read on render — fine for realistic log sizes; cache if logs ever grow large.
    private var calibration: Calibration.Summary? {
        Calibration.summary(from: ReviewLog.records(from: ReviewLog.defaultURL))
    }

    private var memoryCard: some View {
        // Until something's been reviewed, both numbers are nil — show a "study to see this" state
        // rather than hiding the card, so its place on the page (and what it tracks) is visible.
        let hasData = insights.predictedRetention != nil || insights.trueRetention != nil
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .top, spacing: Theme.Spacing.s) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Memory").font(Typography.headline).foregroundStyle(.secondary)
                    if hasData {
                        Text(retentionGraphSubtitle).font(Typography.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if hasData { graphChip }
            }
            if hasData {
                retentionGraphView
                    .frame(height: 140)
                    .contentShape(Rectangle())
                    .onTapGesture { cycleRetentionGraph() }
                retentionLegend
                if let takeaway = insights.retentionTakeaway {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                            .padding(.top, 1)
                        Text(takeaway)
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
                if let calibration {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "scope")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .padding(.top, 1)
                        Text(Calibration.takeaway(calibration))
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 2)
                }
            } else {
                retentionEmptyState
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: Theme.Radius.tile)
    }

    /// A tappable chip naming the current graph; tapping it (or the graph itself) cycles to the next.
    private var graphChip: some View {
        CycleChip(label: retentionGraph.label,
                  accessibility: "Graph: \(retentionGraph.label). Tap to change.",
                  onCycle: cycleRetentionGraph)
    }

    private func cycleRetentionGraph() {
        let all = RetentionGraph.allCases
        let idx = all.firstIndex(of: retentionGraph) ?? 0
        retentionGraphRaw = all[(idx + 1) % all.count].rawValue
    }

    /// Shown before any reviews exist: keeps the card on the dashboard and says what will appear.
    private var retentionEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain.head.profile")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Study some cards to see this")
                .font(Typography.callout)
                .foregroundStyle(.secondary)
            Text("Predicted recall appears after your first review; mature-card retention fills in as cards reach a 21-day interval.")
                .font(Typography.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Memory retention. Study some cards to see this.")
    }

    /// Explains the selected graph's axes — these are hand-drawn charts, so the words carry the
    /// context a Charts-framework axis label would.
    private var retentionGraphSubtitle: String {
        switch retentionGraph {
        case .spread: "Cards by estimated recall now (height = how many cards)"
        case .trend:  "Mature retention each week — last 12 weeks (Y: 50–100%)"
        case .curve:  "Predicted recall vs. days since a review (Y: 50–100%)"
        }
    }

    @ViewBuilder private var retentionGraphView: some View {
        switch retentionGraph {
        case .spread: RecallSpreadChart(buckets: insights.recallBuckets)
        case .trend:  RetentionTrendChart(trend: insights.retentionTrend)
        case .curve:  ForgettingCurveChart(averageInterval: insights.averageIntervalDays)
        }
    }

    private var retentionLegend: some View {
        HStack(spacing: Theme.Spacing.l) {
            retentionLegendItem(percent(insights.predictedRetention), "est. recall now", insights.predictedRetention)
            retentionLegendItem(percent(insights.trueRetention), "mature retention", insights.trueRetention)
            Spacer(minLength: 0)
        }
    }

    private func retentionLegendItem(_ value: String, _ label: String, _ source: Double?) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.retentionTint(source)).frame(width: 9, height: 9)
            Text(value).font(.system(.callout, design: .rounded, weight: .bold)).monospacedDigit().foregroundStyle(Theme.retentionTint(source))
            Text(label).font(Typography.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label)")
    }

    /// Past calendar years (before this year) that have at least one reviewed day — the year-picker
    /// options, most-recent first. Empty ⇒ no picker (just the trailing-year view). Read from the
    /// day-keys' "YYYY-…" prefix, so no calendar math per entry.
    private var availableYears: [Int] {
        let current = calendar.component(.year, from: now)
        var years = Set<Int>()
        for (key, count) in reviewsByDay where count > 0 {
            if let year = Int(key.prefix(4)), year < current { years.insert(year) }
        }
        return years.sorted(by: >)
    }

    /// The selected year, falling back to "Past year" (0) when the stored choice has no data.
    private var resolvedYear: Int { availableYears.contains(heatmapYear) ? heatmapYear : 0 }

    /// Right edge of the heatmap: today for the trailing-year view, else Dec 31 of the chosen year.
    private var heatmapAnchor: Date {
        guard resolvedYear != 0 else { return now }
        return calendar.date(from: DateComponents(year: resolvedYear, month: 12, day: 31)) ?? now
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.s) {
                Text("Activity").font(Typography.headline).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                // Year browsing appears only once there's history in an earlier calendar year;
                // otherwise the heatmap is simply the trailing 12 months, with no chrome.
                if !availableYears.isEmpty {
                    Menu {
                        Button("Past year") { heatmapYear = 0 }
                        Divider()
                        ForEach(availableYears, id: \.self) { year in
                            Button(String(year)) { heatmapYear = year }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(resolvedYear == 0 ? "Past year" : String(resolvedYear))
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(.caption, design: .rounded, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
            ActivityHeatmap(reviewsByDay: reviewsByDay, anchorDate: heatmapAnchor, now: now, calendar: calendar)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: Theme.Radius.tile)
    }

    /// "Your library" — overall maturity, then one breakdown table that the user cycles through the
    /// available groupings (By deck / By category / By section) by tapping a chip, like the Memory
    /// graph. Folds what used to be three separate cards (By deck · By section · Card maturity) into one.
    private var libraryCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                Text("Your library").font(Typography.headline).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                if availableGroupings.count > 1 { groupingChip }
            }
            VStack(alignment: .leading, spacing: 8) {
                MaturityBar(new: insights.newCount, learning: insights.learningCount, mature: insights.matureCount)
                HStack(spacing: Theme.Spacing.l) {
                    legend("New", Theme.Maturity.new, insights.newCount)
                    legend("Learning", Theme.Maturity.learning, insights.learningCount)
                    legend("Mature", Theme.Maturity.mature, insights.matureCount)
                    Spacer(minLength: 0)
                }
            }
            Divider()
            VStack(spacing: Theme.Spacing.s) { groupingRows }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(cornerRadius: Theme.Radius.tile)
    }

    @ViewBuilder private var groupingRows: some View {
        switch resolvedGrouping {
        case .deck:     ForEach(sortedDecks) { deckRow($0) }
        case .category: ForEach(sortedCategories) { categoryRow($0) }
        case .section:  ForEach(sortedSections) { sectionRow($0) }
        }
    }

    /// The groupings worth offering: By deck always; By category only with ≥2 categories; By section
    /// only when some deck uses sections.
    private var availableGroupings: [LibraryGrouping] {
        var groupings: [LibraryGrouping] = [.deck]
        if insights.categories.count >= 2 { groupings.append(.category) }
        if !insights.sections.isEmpty { groupings.append(.section) }
        return groupings
    }
    private var resolvedGrouping: LibraryGrouping {
        let g = LibraryGrouping(rawValue: libraryGroupingRaw) ?? .deck
        return availableGroupings.contains(g) ? g : .deck
    }

    /// Tappable chip naming the current grouping; tap cycles through `availableGroupings`.
    private var groupingChip: some View {
        CycleChip(label: resolvedGrouping.label,
                  accessibility: "Grouped \(resolvedGrouping.label). Tap to change.",
                  onCycle: cycleGrouping)
    }
    private func cycleGrouping() {
        let avail = availableGroupings
        let idx = avail.firstIndex(of: resolvedGrouping) ?? 0
        libraryGroupingRaw = avail[(idx + 1) % avail.count].rawValue
    }

    private var sortedCategories: [StudyInsights.CategoryStat] {
        insights.categories.sorted { ($0.due, $0.totalCards) > ($1.due, $1.totalCards) }
    }

    private func categoryRow(_ cat: StudyInsights.CategoryStat) -> some View {
        groupingRow(name: cat.name, due: cat.due, total: cat.totalCards,
                    new: cat.newCount, learning: cat.learningCount, mature: cat.matureCount) {
            Image(systemName: "folder.fill").font(.system(size: 15)).foregroundStyle(Theme.accent).frame(width: 22)
        }
    }

    /// Most actionable first: most due, then largest.
    private var sortedDecks: [StudyInsights.DeckStat] {
        insights.perDeck.sorted { ($0.due, $0.totalCards) > ($1.due, $1.totalCards) }
    }

    private func deckRow(_ deck: StudyInsights.DeckStat) -> some View {
        groupingRow(name: deck.name, due: deck.due, total: deck.totalCards,
                    new: deck.newCount, learning: deck.learningCount, mature: deck.matureCount) {
            DeckIconChip(icon: deck.icon, colorHex: deck.colorHex, size: 22)
        }
    }

    /// Most actionable first: most due, then largest.
    private var sortedSections: [StudyInsights.SectionStat] {
        insights.sections.sorted { ($0.due, $0.totalCards) > ($1.due, $1.totalCards) }
    }

    private func sectionRow(_ section: StudyInsights.SectionStat) -> some View {
        let label = section.section.isEmpty ? "\(section.deckName) · No section" : "\(section.deckName) · \(section.section)"
        return groupingRow(name: label, due: section.due, total: section.totalCards,
                           new: section.newCount, learning: section.learningCount, mature: section.matureCount) {
            DeckIconChip(icon: section.icon, colorHex: section.colorHex, size: 22)
        }
    }

    /// One row of the "Your library" breakdown — icon · name · due pill · card count, then a maturity
    /// bar with its percent. Shared by By-deck / By-category / By-section, which differ only in the
    /// leading icon and the name.
    private func groupingRow<Icon: View>(
        name: String, due: Int, total: Int, new: Int, learning: Int, mature: Int,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        let maturePct = total > 0 ? mature * 100 / total : 0
        return HStack(spacing: 10) {
            icon()
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(name).font(Typography.body).lineLimit(1)
                    Spacer(minLength: 4)
                    if due > 0 { DuePill(count: due) }
                    Text("\(total)").font(Typography.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                HStack(spacing: 8) {
                    MaturityBar(new: new, learning: learning, mature: mature).frame(height: 6)
                    Text("\(maturePct)%")
                        .font(.system(.caption2, design: .rounded, weight: .semibold))
                        .foregroundStyle(.secondary).monospacedDigit().frame(width: 34, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(total) cards, \(due) due, \(maturePct) percent mature")
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

/// The small "N due" capsule shown in the library breakdown rows.
private struct DuePill: View {
    let count: Int
    var body: some View {
        Text("\(count) due")
            .font(.system(.caption2, design: .rounded, weight: .bold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.orange.opacity(Theme.Opacity.fillSubtle), in: Capsule())
    }
}

/// A small tappable capsule naming the current choice with a cycle glyph; tapping cycles to the
/// next. Shared by the Insights Memory-graph and library-grouping chips.
private struct CycleChip: View {
    let label: String
    let accessibility: String
    let onCycle: () -> Void

    var body: some View {
        Button(action: onCycle) {
            HStack(spacing: 3) {
                Text(label)
                Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(.caption, design: .rounded, weight: .medium))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Theme.accent.opacity(Theme.Opacity.fillSubtle), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }
}

/// GitHub-style contribution grid: weeks of day cells, tinted by that day's review count. Fills
/// the available width (as many weeks as fit, up to the selected range). Drawn in plain SwiftUI (no
/// Charts dependency, no scroll view), so it renders under `ImageRenderer`.
struct ActivityHeatmap: View {
    let reviewsByDay: [String: Int]
    /// The last day shown (right edge). Defaults to today — the trailing-12-months view. A calendar-
    /// year selection passes Dec 31 of that year, so the grid spans that whole year instead.
    var anchorDate: Date = .now
    /// Real "today": used to leave future cells blank and to find today's column. Distinct from
    /// `anchorDate` so a past-year view (anchored earlier) still knows where, if anywhere, today is.
    var now: Date = .now
    var calendar: Calendar = .current
    /// Requested number of week columns (a year ≈ 53); still clamped to whatever fits the width.
    var weeks: Int = 53
    var cell: CGFloat = 14

    private let gap: CGFloat = 3
    private let maxWeeks = 53

    var body: some View {
        GeometryReader { geo in
            let columns = min(max(Int((geo.size.width + gap) / (cell + gap)), 1), min(maxWeeks, weeks))
            let anchor = calendar.startOfDay(for: anchorDate)
            let weekday = calendar.component(.weekday, from: anchor)
            let startOfWeek = calendar.date(byAdding: .day, value: -(weekday - 1), to: anchor) ?? anchor
            let firstDay = calendar.date(byAdding: .day, value: -((columns - 1) * 7), to: startOfWeek) ?? anchor
            // Scale colors to the user's busiest day. Computed once per render and threaded down —
            // not recomputed inside `color(_:)` for each of the ~371 cells.
            let maxCount = max(reviewsByDay.values.max() ?? 0, 1)
            let gridWidth = CGFloat(columns) * cell + CGFloat(columns - 1) * gap
            VStack(alignment: .leading, spacing: 4) {
                monthLabels(weeks: columns, firstDay: firstDay)
                grid(weeks: columns, firstDay: firstDay, maxCount: maxCount, gridWidth: gridWidth)
                legend
            }
            .frame(width: gridWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)   // center the block (no left-side dead space)
        }
        .frame(height: 7 * cell + 6 * gap + 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity heatmap of daily reviews")
    }

    /// The day grid, drawn in a single `Canvas` — one view and one draw pass instead of ~371
    /// `RoundedRectangle` subviews, which was the bulk of the Insights render cost. Counts are placed
    /// by integer day-number (no per-cell calendar call); cells after today are left blank.
    private func grid(weeks: Int, firstDay: Date, maxCount: Int, gridWidth: CGFloat) -> some View {
        let firstDayNumber = StudyStats.dayNumber(fromKey: StudyStats.dayKey(firstDay, calendar: calendar)) ?? 0
        let cellCount = weeks * 7
        var counts = [Int](repeating: 0, count: cellCount)
        for (key, c) in reviewsByDay where c > 0 {
            if let n = StudyStats.dayNumber(fromKey: key) {
                let idx = n - firstDayNumber
                if idx >= 0, idx < cellCount { counts[idx] = c }
            }
        }
        let todayIndex = (StudyStats.dayNumber(fromKey: StudyStats.dayKey(now, calendar: calendar)) ?? firstDayNumber) - firstDayNumber
        let step = cell + gap
        return Canvas { context, _ in
            for i in 0..<cellCount where i <= todayIndex {   // cells after today stay blank
                let rect = CGRect(x: CGFloat(i / 7) * step, y: CGFloat(i % 7) * step, width: cell, height: cell)
                context.fill(Path(roundedRect: rect, cornerRadius: 2, style: .continuous),
                             with: .color(color(counts[i], max: maxCount)))
            }
        }
        .frame(width: gridWidth, height: 7 * cell + 6 * gap)
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

/// Which "Your library" breakdown the Insights card shows; tap the chip to cycle. Persisted via
/// `@AppStorage`.
enum LibraryGrouping: Int, CaseIterable, Identifiable {
    case deck = 0, category = 1, section = 2
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .deck:     "By deck"
        case .category: "By category"
        case .section:  "By section"
        }
    }
}

/// Which Memory-retention graph the Insights card shows, persisted via `@AppStorage`.
enum RetentionGraph: Int, CaseIterable, Identifiable {
    case spread = 0, trend = 1, curve = 2
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .spread: "Spread"
        case .trend:  "Trend"
        case .curve:  "Curve"
        }
    }
}

/// Reviewed cards bucketed by predicted recall — a 4-bar histogram (<50 / 50–70 / 70–90 / 90+ %),
/// single-hue so stronger recall reads darker. Plain SwiftUI, renders under `ImageRenderer`.
struct RecallSpreadChart: View {
    let buckets: [Int]
    private let labels = ["<50", "50–70", "70–90", "90+"]
    private var maxCount: Int { max(buckets.max() ?? 0, 1) }

    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 10
            let barWidth = max((geo.size.width - spacing * 3) / 4, 1)
            let areaHeight = geo.size.height - 22
            HStack(alignment: .bottom, spacing: spacing) {
                ForEach(0..<4, id: \.self) { i in
                    VStack(spacing: 4) {
                        Spacer(minLength: 0)
                        Text("\(count(i))")
                            .font(.system(size: 9, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.accent.opacity([0.30, 0.50, 0.72, 1.0][i]))
                            .frame(width: barWidth, height: count(i) > 0 ? max(areaHeight * CGFloat(count(i)) / CGFloat(maxCount), 3) : 0)
                        Text(labels[i]).font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recall spread: " + zip(labels, buckets).map { "\($0.1) cards at \($0.0) percent" }.joined(separator: ", "))
    }

    private func count(_ i: Int) -> Int { buckets.indices.contains(i) ? buckets[i] : 0 }
}

/// A shared 100 / 75 / 50% Y-axis gutter for the retention charts (their Y axes span 50–100%).
private struct RetentionYAxis: View {
    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text("100%"); Spacer(); Text("75%"); Spacer(); Text("50%")
        }
        .font(.system(size: 8, design: .rounded))
        .foregroundStyle(.tertiary)
        .frame(width: 26)
    }
}

/// Mature retention over recent weeks — an area + line on a labeled 50–100% axis, with weeks that
/// had no mature reviews left as gaps. Plain SwiftUI (Path), renders under `ImageRenderer`.
struct RetentionTrendChart: View {
    let trend: [Double?]
    private let floorY = 0.5   // retention rarely dips below 50%; gives the line room to vary

    var body: some View {
        let points: [(Int, Double)] = trend.enumerated().compactMap { i, v in v.map { (i, $0) } }
        return HStack(alignment: .top, spacing: 5) {
            RetentionYAxis()
            VStack(spacing: 3) {
                plot(points)
                HStack {
                    Text("\(trend.count) wks ago")
                    Spacer()
                    Text("now")
                }
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mature retention over the last \(trend.count) weeks, on a 50 to 100 percent scale")
    }

    @ViewBuilder private func plot(_ points: [(Int, Double)]) -> some View {
        GeometryReader { geo in
            if points.count < 2 {
                Text(points.isEmpty ? "No mature reviews yet" : "Not enough mature reviews yet")
                    .font(Typography.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let span = CGFloat(max(trend.count - 1, 1))
                let yFor: (Double) -> CGFloat = { v in
                    geo.size.height * (1 - CGFloat((min(max(v, floorY), 1) - floorY) / (1 - floorY)))
                }
                let pos: (Int, Double) -> CGPoint = { i, v in CGPoint(x: geo.size.width * CGFloat(i) / span, y: yFor(v)) }
                ZStack {
                    ForEach([1.0, 0.75, 0.5], id: \.self) { v in
                        let y = yFor(v)
                        Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                            .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                    }
                    Path { p in
                        p.move(to: CGPoint(x: pos(points[0].0, points[0].1).x, y: geo.size.height))
                        for (i, v) in points { p.addLine(to: pos(i, v)) }
                        p.addLine(to: CGPoint(x: pos(points[points.count - 1].0, points[points.count - 1].1).x, y: geo.size.height))
                        p.closeSubpath()
                    }.fill(Theme.accent.opacity(0.15))
                    Path { p in
                        for (idx, point) in points.enumerated() {
                            let cg = pos(point.0, point.1)
                            if idx == 0 { p.move(to: cg) } else { p.addLine(to: cg) }
                        }
                    }.stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    ForEach(points.indices, id: \.self) { idx in
                        Circle().fill(Theme.accent).frame(width: 5, height: 5).position(pos(points[idx].0, points[idx].1))
                    }
                }
            }
        }
    }
}

/// The forgetting curve R = 0.9^(t / interval) out to ~4× the average interval, on a labeled
/// 50–100% axis, with a dashed marker at the due point (where recall hits the 90% target). Plain
/// SwiftUI (Path), renders under `ImageRenderer`.
struct ForgettingCurveChart: View {
    let averageInterval: Double
    private let floorR = 0.5   // map [50%, 100%] to the height so the curve isn't flat

    var body: some View {
        let interval = max(averageInterval, 1)
        let horizon = interval * 4
        return HStack(alignment: .top, spacing: 5) {
            RetentionYAxis()
            VStack(spacing: 3) {
                plot(interval: interval, horizon: horizon)
                HStack {
                    Text("0d")
                    Spacer()
                    Text("\(Int(horizon.rounded()))d")
                }
                .font(.system(size: 8, design: .rounded))
                .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Predicted recall over \(Int(horizon.rounded())) days; due at about \(Int(interval.rounded())) days, on a 50 to 100 percent scale")
    }

    private func plot(interval: Double, horizon: Double) -> some View {
        GeometryReader { geo in
            let steps = 60
            let yFor: (Double) -> CGFloat = { r in
                geo.size.height * (1 - CGFloat((min(max(r, floorR), 1) - floorR) / (1 - floorR)))
            }
            let pos: (Double) -> CGPoint = { t in CGPoint(x: geo.size.width * CGFloat(t / horizon), y: yFor(pow(0.9, t / interval))) }
            let dueX = geo.size.width * CGFloat(interval / horizon)
            ZStack {
                ForEach([1.0, 0.75, 0.5], id: \.self) { v in
                    let y = yFor(v)
                    Path { $0.move(to: CGPoint(x: 0, y: y)); $0.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                }
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height))
                    for s in 0...steps { p.addLine(to: pos(horizon * Double(s) / Double(steps))) }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.closeSubpath()
                }.fill(Theme.accent.opacity(0.15))
                Path { p in
                    for s in 0...steps {
                        let cg = pos(horizon * Double(s) / Double(steps))
                        if s == 0 { p.move(to: cg) } else { p.addLine(to: cg) }
                    }
                }.stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                Path { p in p.move(to: CGPoint(x: dueX, y: 0)); p.addLine(to: CGPoint(x: dueX, y: geo.size.height)) }
                    .stroke(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                Text("due ~\(Int(interval.rounded()))d")
                    .font(.system(size: 8, design: .rounded)).foregroundStyle(.secondary)
                    .fixedSize()
                    .position(x: dueX, y: 7)
            }
        }
    }
}

/// A thin stacked bar showing the New / Learning / Mature proportions of the library. On macOS,
/// hovering a single colored segment pops up just that band's count — unless `showsPopover` is off
/// (e.g. the deck page, which already prints the counts as "N Cards / N Due" beside the bar).
struct MaturityBar: View {
    let new: Int
    let learning: Int
    let mature: Int
    /// macOS hover popover per segment. Disabled where the counts are already shown alongside.
    var showsPopover = true

    #if os(macOS)
    @State private var hovered: Int?   // which segment (0=New, 1=Learning, 2=Mature) is hovered
    #endif

    private var total: Int { max(new + learning + mature, 1) }

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                segment(Theme.Maturity.new, new, 0, "New", geo.size.width)
                segment(Theme.Maturity.learning, learning, 1, "Learning", geo.size.width)
                segment(Theme.Maturity.mature, mature, 2, "Mature", geo.size.width)
            }
        }
        .frame(height: 10)
        .background(Color.primary.opacity(0.06))
        .clipShape(Capsule())
    }

    private func segment(_ color: Color, _ count: Int, _ index: Int, _ label: String, _ width: CGFloat) -> some View {
        color
            .frame(width: width * CGFloat(count) / CGFloat(total))
            #if os(macOS)
            // Each segment is independently hoverable; the popover sits above it (cursor stays on
            // the bar) and shows just this band's count.
            .onHover { inside in
                guard showsPopover else { return }
                if inside { hovered = index } else if hovered == index { hovered = nil }
            }
            .popover(isPresented: valuePopover(index), arrowEdge: .top) {
                VStack(spacing: 1) {
                    Text("\(count)").font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
            }
            #endif
    }

    #if os(macOS)
    private func valuePopover(_ index: Int) -> Binding<Bool> {
        Binding(get: { showsPopover && hovered == index }, set: { if !$0 && hovered == index { hovered = nil } })
    }
    #endif
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
