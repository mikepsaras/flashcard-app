import Foundation
import SwiftData

/// A pure snapshot of study + library statistics for the Insights screen. Built from the decks
/// plus the `StudyStats` day logs; deterministic given its inputs, so the aggregation is
/// unit-tested and the view stays a dumb renderer.
struct StudyInsights: Equatable {
    var reviewsToday = 0
    var reviewsThisWeek = 0
    var reviewsLastWeek = 0
    var reviewsAllTime = 0
    /// Mean reviews across days that had at least one review (0 when none).
    var dailyAverage = 0
    var currentStreak = 0
    var longestStreak = 0
    /// correct / reviews; `nil` when there are no reviews to divide by.
    var accuracyAllTime: Double?
    var accuracyThisWeek: Double?
    var accuracyLastWeek: Double?
    /// Total correct reviews all-time (the numerator behind accuracyAllTime).
    var correctAllTime = 0
    /// Estimated mean recall *right now* across reviewed cards, from each card's schedule via a
    /// 90%-at-due forgetting curve; `nil` when nothing has been reviewed yet. Distinct from
    /// `accuracyAllTime` (a historical pass rate) — this is a current-state memory estimate.
    var predictedRetention: Double?
    /// Predicted recall at look-aheads now / +7d / +30d (days → mean recall), for the Insights hero
    /// ring's tap-to-cycle timeframe. Empty until something's been reviewed.
    var predictedRecallByHorizon: [Int: Double] = [:]
    /// Reviewed review-units (card × scheduled direction) backing `predictedRetention`.
    var scheduledUnits = 0
    /// Reviewed units bucketed by predicted recall: [<50%, 50–70%, 70–90%, 90–100%] — the
    /// "Spread" retention graph.
    var recallBuckets: [Int] = [0, 0, 0, 0]
    /// Mean scheduled interval (days) across reviewed units — anchors the forgetting-"Curve" graph.
    var averageIntervalDays = 0.0
    /// Mature retention per week over the recent past (oldest → newest), `nil` for weeks with no
    /// mature reviews — the "Trend" retention graph.
    var retentionTrend: [Double?] = []
    /// Measured pass rate on *mature* cards (Anki's "true retention"); `nil` until a mature card is
    /// reviewed (the log starts empty and fills as you study). All-time.
    var trueRetention: Double?
    /// Mature reviews logged and their correct subset (the denominator / numerator of trueRetention).
    var matureReviewCount = 0
    var matureCorrectCount = 0
    var totalCards = 0
    var newCount = 0
    var learningCount = 0
    var matureCount = 0
    var dueNow = 0
    /// Review units due within the next 7 days (includes anything overdue).
    var dueThisWeek = 0
    /// Reviews coming due each day for the next two weeks; index 0 is today and folds in overdue.
    var dueForecast: [Int] = []
    /// Per-deck breakdown for the "where to focus" table, in deck order.
    var perDeck: [DeckStat] = []
    /// Per-section breakdown (only for decks that use sections), for the "By section" table.
    var sections: [SectionStat] = []
    /// Per-category breakdown — whole decks grouped by their library Category (`Deck.section`), for
    /// the optional "By category" table. Only meaningful when ≥2 categories exist.
    var categories: [CategoryStat] = []

    /// One deck's at-a-glance composition for the per-deck breakdown.
    struct DeckStat: Equatable, Identifiable {
        var id: UUID
        var name: String
        var colorHex: String
        var icon: String = ""
        var totalCards: Int
        var due: Int
        var newCount: Int
        var learningCount: Int
        var matureCount: Int
    }

    /// One section's composition (within its deck) for the per-section breakdown.
    struct SectionStat: Equatable, Identifiable {
        var id: String
        var deckName: String
        var colorHex: String
        var icon: String = ""
        var section: String          // "" ⇒ the deck's unsectioned cards
        var totalCards: Int
        var due: Int
        var newCount: Int
        var learningCount: Int
        var matureCount: Int
    }

    /// One library Category's aggregate (the sum of its decks) for the per-category breakdown.
    struct CategoryStat: Equatable, Identifiable {
        var id: String               // the category name; "" ⇒ Uncategorized
        var name: String
        var totalCards: Int
        var due: Int
        var newCount: Int
        var learningCount: Int
        var matureCount: Int
    }

    /// A plain-language reading of the retention numbers for the card's footer: the predicted-recall
    /// level, plus a nudge based on mature retention vs. the 90% target — or, before there's enough
    /// mature data, a pointer to the weakest cards. `nil` until something has been reviewed.
    var retentionTakeaway: String? {
        guard let predicted = predictedRetention else { return nil }
        let recall = "You'd recall about \(Int((predicted * 100).rounded()))% of your cards right now."
        // Mature retention needs a small sample before it's worth coaching on.
        if let mature = trueRetention, matureReviewCount >= 10 {
            let m = Int((mature * 100).rounded())
            let note: String
            if m >= 90 {
                note = "Mature retention of \(m)% is at the 90% target — your schedule's working."
            } else if m >= 80 {
                note = "Mature retention of \(m)% is just under the 90% target; reviewing a little more often would lift it."
            } else {
                note = "Mature retention of \(m)% is below the 90% target — those cards are slipping, so study them more often."
            }
            return "\(recall) \(note)"
        }
        let weak = recallBuckets.prefix(2).reduce(0, +)   // cards under 70% predicted recall
        if weak > 0 {
            return "\(recall) \(weak) card\(weak == 1 ? " is" : "s are") under 70% recall — review those next."
        }
        return "\(recall) Keep reviewing cards as they mature (a 21+ day interval) to start tracking true retention."
    }

    /// An interval ≥ this many days is considered "mature" (Anki's convention).
    static let matureIntervalDays = 21
    /// How many days of upcoming due cards the forecast covers.
    static let forecastDays = 14
    /// Target recall at a card's due date — the SM-2/SuperMemo convention behind predicted recall:
    /// estimated recall decays as `targetRetentionAtDue^(daysSinceReview / interval)`, hitting this
    /// at the due date (and falling below it once overdue).
    static let targetRetentionAtDue = 0.9
    /// How many weeks of mature-retention history the "Trend" graph covers.
    static let retentionTrendWeeks = 12

    /// Average predicted recall across a deck's reviewed review-units, `daysAhead` days from `now`,
    /// using the same forgetting curve as `predictedRetention` (R = targetRetentionAtDue^(elapsed /
    /// interval)). Returns the mean recall (nil when nothing's been reviewed) and the unit count it
    /// averaged — callers gate on a minimum sample so a one-card deck doesn't read as the whole deck.
    /// Pure given its inputs; `@MainActor` only because it reads `@Model` card scalars.
    @MainActor
    static func predictedRecall(
        forCards cards: [Card], studyReversed: Bool, daysAhead: Int = 0, now: Date = .now
    ) -> (recall: Double?, units: Int) {
        let directions: [ReviewDirection] = studyReversed ? [.forward, .reverse] : [.forward]
        var sum = 0.0, units = 0
        let ahead = Double(daysAhead)
        for card in cards {
            for direction in directions {
                guard let last = card.lastReviewedAt(direction) else { continue }
                let interval = Double(max(card.schedulingState(direction).interval, 1))
                let elapsed = max(now.timeIntervalSince(last) / 86_400, 0) + ahead
                sum += pow(targetRetentionAtDue, elapsed / interval)
                units += 1
            }
        }
        return (units > 0 ? sum / Double(units) : nil, units)
    }

    @MainActor
    static func make(
        decks: [Deck],
        reviewsByDay: [String: Int],
        correctByDay: [String: Int],
        matureByDay: [String: Int] = [:],
        matureCorrectByDay: [String: Int] = [:],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> StudyInsights {
        var insights = StudyInsights()

        // Activity (from the day logs).
        insights.reviewsAllTime = reviewsByDay.values.reduce(0, +)
        insights.reviewsToday = reviewsByDay[StudyStats.dayKey(now, calendar: calendar)] ?? 0
        insights.currentStreak = StudyStats.streak(in: reviewsByDay, asOf: now, calendar: calendar)
        insights.longestStreak = StudyStats.longestStreak(in: reviewsByDay, calendar: calendar)

        // Rolling 7-day windows for this week vs last week.
        func windowKeys(_ range: Range<Int>) -> Set<String> {
            Set(range.compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: now)
                    .map { StudyStats.dayKey($0, calendar: calendar) }
            })
        }
        func sum(_ log: [String: Int], _ keys: Set<String>) -> Int { keys.reduce(0) { $0 + (log[$1] ?? 0) } }
        func ratio(_ correct: Int, _ reviews: Int) -> Double? { reviews > 0 ? Double(correct) / Double(reviews) : nil }
        let thisWeek = windowKeys(0..<7)
        let lastWeek = windowKeys(7..<14)

        insights.reviewsThisWeek = sum(reviewsByDay, thisWeek)
        insights.reviewsLastWeek = sum(reviewsByDay, lastWeek)
        insights.correctAllTime = correctByDay.values.reduce(0, +)
        insights.accuracyAllTime = ratio(insights.correctAllTime, insights.reviewsAllTime)
        insights.accuracyThisWeek = ratio(sum(correctByDay, thisWeek), insights.reviewsThisWeek)
        insights.accuracyLastWeek = ratio(sum(correctByDay, lastWeek), insights.reviewsLastWeek)

        // True retention — measured pass rate on mature cards (Anki's convention), all-time. `nil`
        // until the (initially empty) mature log has data.
        insights.matureReviewCount = matureByDay.values.reduce(0, +)
        insights.matureCorrectCount = matureCorrectByDay.values.reduce(0, +)
        insights.trueRetention = ratio(insights.matureCorrectCount, insights.matureReviewCount)

        let activeDays = reviewsByDay.values.filter { $0 > 0 }.count
        insights.dailyAverage = activeDays > 0
            ? Int((Double(insights.reviewsAllTime) / Double(activeDays)).rounded()) : 0

        // Library composition, due windows, per-deck + per-section breakdowns, and the due
        // forecast — all in one pass over each deck's cards. No intermediate `ReviewItem` arrays
        // are built, and a sectioned deck's cards aren't walked a second time.
        let weekAhead = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let startToday = calendar.startOfDay(for: now)
        // Anything due past here can't land in the forecast, so we skip the (costly) day-bucketing
        // calendar math for it — most cards in a mature library are due well beyond two weeks.
        let forecastEnd = calendar.date(byAdding: .day, value: forecastDays, to: startToday) ?? now
        var forecast = Array(repeating: 0, count: forecastDays)
        // Predicted-recall accumulators (mean of 0.9^(elapsed/interval) over reviewed units), plus
        // a recall histogram and an interval sum for the "Spread" / "Curve" graphs.
        var retentionSum = 0.0, retentionSum7 = 0.0, retentionSum30 = 0.0
        var retentionUnits = 0
        var intervalSum = 0.0
        var buckets = [0, 0, 0, 0]
        var byCategory: [String: CategoryStat] = [:]   // deck-level Category → aggregate
        for deck in decks {
            var stat = DeckStat(id: deck.id, name: deck.displayName, colorHex: deck.colorHex,
                                icon: deck.icon, totalCards: 0, due: 0, newCount: 0, learningCount: 0, matureCount: 0)

            // Per-section accumulation, for decks that use sections. Capture the deck's *scalar*
            // fields (not the @Model itself) so the `slot` helper closes over nothing non-Sendable
            // — Swift 6 strict concurrency flags that under the Release config even where Debug doesn't.
            let usesSections = !deck.sectionOrder.isEmpty
            let deckID = deck.id.uuidString, deckName = deck.displayName, colorHex = deck.colorHex, deckIcon = deck.icon
            var bySection: [String: SectionStat] = [:]
            func slot(_ name: String) -> SectionStat {
                bySection[name] ?? SectionStat(id: "\(deckID)-\(name)", deckName: deckName, colorHex: colorHex,
                                               icon: deckIcon, section: name, totalCards: 0, due: 0, newCount: 0, learningCount: 0, matureCount: 0)
            }

            // Forward for every card, plus reverse when the deck studies both ways. Read once.
            let reversed = deck.studyReversed
            for card in deck.cardArray {
                // SwiftData @Model property access is ~1–2µs each (machinery, not a plain field), so
                // read every scalar this loop needs ONCE into a local instead of re-reading per use —
                // this is the bulk of make()'s cost on a large library.
                let fInterval = card.interval, rInterval = card.reverseInterval
                let fDue = card.dueDate, rDue = card.reverseDueDate
                let fLast = card.lastReviewedAt, rLast = card.reverseLastReviewedAt

                insights.totalCards += 1
                stat.totalCards += 1
                let isNew = fLast == nil && rLast == nil
                // Best interval the card earned in any direction — independent of the deck's
                // current `studyReversed` toggle.
                let isMature = !isNew && max(fInterval, rInterval) >= matureIntervalDays
                if isNew { insights.newCount += 1; stat.newCount += 1 }
                else if isMature { insights.matureCount += 1; stat.matureCount += 1 }
                else { insights.learningCount += 1; stat.learningCount += 1 }

                var cardDue = 0
                for unit in 0..<(reversed ? 2 : 1) {
                    let due = unit == 0 ? fDue : rDue
                    let last = unit == 0 ? fLast : rLast
                    let unitInterval = unit == 0 ? fInterval : rInterval
                    if due <= now { insights.dueNow += 1; stat.due += 1; cardDue += 1 }
                    if due <= weekAhead { insights.dueThisWeek += 1 }
                    // Bucket into the forecast (overdue folds into today, index 0); skip cards due
                    // past the window. Offset is days-from-today via elapsed seconds — no per-card
                    // calendar call. (A DST day is 23/25h, so this can be off by one around a
                    // transition; immaterial for a 14-day forecast bar chart.)
                    if due <= forecastEnd {
                        let offset = max(0, Int(due.timeIntervalSince(startToday) / 86_400))
                        if offset < forecastDays { forecast[offset] += 1 }
                    }

                    // Predicted recall now for this scheduled unit: 0.9^(daysSinceReview / interval),
                    // i.e. ~90% at the due date, decaying past it. Only reviewed units contribute
                    // (a never-seen card has nothing to recall). Interval floored at 1 day.
                    if let last {
                        let intervalDays = Double(max(unitInterval, 1))
                        let elapsed = max(now.timeIntervalSince(last) / 86_400, 0)
                        let r = pow(targetRetentionAtDue, elapsed / intervalDays)
                        retentionSum += r
                        retentionSum7 += pow(targetRetentionAtDue, (elapsed + 7) / intervalDays)
                        retentionSum30 += pow(targetRetentionAtDue, (elapsed + 30) / intervalDays)
                        retentionUnits += 1
                        intervalSum += intervalDays
                        buckets[r < 0.5 ? 0 : r < 0.7 ? 1 : r < 0.9 ? 2 : 3] += 1
                    }
                }

                if usesSections {
                    let cardSection = card.section
                    var s = slot(cardSection)
                    s.totalCards += 1
                    if isNew { s.newCount += 1 } else if isMature { s.matureCount += 1 } else { s.learningCount += 1 }
                    s.due += cardDue
                    bySection[cardSection] = s
                }
            }
            insights.perDeck.append(stat)

            // Fold this deck into its library Category aggregate ("" ⇒ Uncategorized).
            let category = deck.section
            var cat = byCategory[category] ?? CategoryStat(id: category, name: category.isEmpty ? "Uncategorized" : category,
                                                           totalCards: 0, due: 0, newCount: 0, learningCount: 0, matureCount: 0)
            cat.totalCards += stat.totalCards
            cat.due += stat.due
            cat.newCount += stat.newCount
            cat.learningCount += stat.learningCount
            cat.matureCount += stat.matureCount
            byCategory[category] = cat

            // Sections listed in the deck's own order, unsectioned last; empty (and orphan) sections
            // omitted — mirroring the deck-detail grouping.
            if usesSections {
                for name in deck.sectionOrder + [""] {
                    if let s = bySection[name], s.totalCards > 0 { insights.sections.append(s) }
                }
            }
        }
        insights.dueForecast = forecast
        // Most-actionable first: most due, then largest.
        insights.categories = byCategory.values.sorted { ($0.due, $0.totalCards) > ($1.due, $1.totalCards) }
        insights.scheduledUnits = retentionUnits
        insights.predictedRetention = retentionUnits > 0 ? retentionSum / Double(retentionUnits) : nil
        if retentionUnits > 0 {
            let n = Double(retentionUnits)
            insights.predictedRecallByHorizon = [0: retentionSum / n, 7: retentionSum7 / n, 30: retentionSum30 / n]
        }
        insights.recallBuckets = buckets
        insights.averageIntervalDays = retentionUnits > 0 ? intervalSum / Double(retentionUnits) : 0

        // Weekly mature retention over the recent past (oldest → newest), from the mature day-logs.
        var trend: [Double?] = []
        for week in stride(from: retentionTrendWeeks - 1, through: 0, by: -1) {
            var rev = 0, cor = 0
            for dayInWeek in 0..<7 {
                guard let day = calendar.date(byAdding: .day, value: -(week * 7 + dayInWeek), to: now) else { continue }
                let key = StudyStats.dayKey(day, calendar: calendar)
                rev += matureByDay[key] ?? 0
                cor += matureCorrectByDay[key] ?? 0
            }
            trend.append(rev > 0 ? Double(cor) / Double(rev) : nil)
        }
        insights.retentionTrend = trend
        return insights
    }
}

/// The deck-page memory-retention ring's look-ahead — tap the ring to cycle. Persisted via
/// `@AppStorage` (raw value = days ahead; 0 = "now").
enum RetentionHorizon: Int, CaseIterable, Identifiable {
    case now = 0, week = 7, month = 30
    var id: Int { rawValue }
    var days: Int { rawValue }
    /// Trailing phrase for the label "recall …".
    var phrase: String {
        switch self {
        case .now:   "now"
        case .week:  "in 1 week"
        case .month: "in 1 month"
        }
    }
    var next: RetentionHorizon {
        switch self {
        case .now:   .week
        case .week:  .month
        case .month: .now
        }
    }
}
