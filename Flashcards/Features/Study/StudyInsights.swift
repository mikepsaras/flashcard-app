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

    /// One deck's at-a-glance composition for the per-deck breakdown.
    struct DeckStat: Equatable, Identifiable {
        var id: UUID
        var name: String
        var colorHex: String
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
        var section: String          // "" ⇒ the deck's unsectioned cards
        var totalCards: Int
        var due: Int
        var newCount: Int
        var learningCount: Int
        var matureCount: Int
    }

    /// An interval ≥ this many days is considered "mature" (Anki's convention).
    static let matureIntervalDays = 21
    /// How many days of upcoming due cards the forecast covers.
    static let forecastDays = 14

    @MainActor
    static func make(
        decks: [Deck],
        reviewsByDay: [String: Int],
        correctByDay: [String: Int],
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

        let activeDays = reviewsByDay.values.filter { $0 > 0 }.count
        insights.dailyAverage = activeDays > 0
            ? Int((Double(insights.reviewsAllTime) / Double(activeDays)).rounded()) : 0

        // Library composition, due windows, per-deck + per-section breakdowns, and the due
        // forecast — all in one pass over each deck's cards. No intermediate `ReviewItem` arrays
        // are built, and a sectioned deck's cards aren't walked a second time.
        let weekAhead = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let startToday = calendar.startOfDay(for: now)
        var forecast = Array(repeating: 0, count: forecastDays)
        for deck in decks {
            var stat = DeckStat(id: deck.id, name: deck.displayName, colorHex: deck.colorHex,
                                totalCards: 0, due: 0, newCount: 0, learningCount: 0, matureCount: 0)

            // Per-section accumulation, for decks that use sections. Capture the deck's *scalar*
            // fields (not the @Model itself) so the `slot` helper closes over nothing non-Sendable
            // — Swift 6 strict concurrency flags that under the Release config even where Debug doesn't.
            let usesSections = !deck.sectionOrder.isEmpty
            let deckID = deck.id.uuidString, deckName = deck.displayName, colorHex = deck.colorHex
            var bySection: [String: SectionStat] = [:]
            func slot(_ name: String) -> SectionStat {
                bySection[name] ?? SectionStat(id: "\(deckID)-\(name)", deckName: deckName, colorHex: colorHex,
                                               section: name, totalCards: 0, due: 0, newCount: 0, learningCount: 0, matureCount: 0)
            }

            // Forward for every card, plus reverse when the deck studies both ways — the same units
            // `deck.allReviewItems` yields, counted directly off the card to skip the allocation.
            let directions: [ReviewDirection] = deck.studyReversed ? [.forward, .reverse] : [.forward]
            for card in deck.cardArray {
                insights.totalCards += 1
                stat.totalCards += 1
                let isNew = !card.hasBeenReviewed
                // Best interval the card earned in any direction — independent of the deck's
                // current `studyReversed` toggle.
                let isMature = !isNew && max(card.interval, card.reverseInterval) >= matureIntervalDays
                if isNew { insights.newCount += 1; stat.newCount += 1 }
                else if isMature { insights.matureCount += 1; stat.matureCount += 1 }
                else { insights.learningCount += 1; stat.learningCount += 1 }

                var cardDue = 0
                for direction in directions {
                    let due = card.dueDate(direction)
                    if due <= now { insights.dueNow += 1; stat.due += 1; cardDue += 1 }
                    if due <= weekAhead { insights.dueThisWeek += 1 }
                    // Bucket into the forecast; overdue folds into today (index 0).
                    let dueDay = calendar.startOfDay(for: due)
                    let offset = max(0, calendar.dateComponents([.day], from: startToday, to: dueDay).day ?? 0)
                    if offset < forecastDays { forecast[offset] += 1 }
                }

                if usesSections {
                    var s = slot(card.section)
                    s.totalCards += 1
                    if isNew { s.newCount += 1 } else if isMature { s.matureCount += 1 } else { s.learningCount += 1 }
                    s.due += cardDue
                    bySection[card.section] = s
                }
            }
            insights.perDeck.append(stat)

            // Sections listed in the deck's own order, unsectioned last; empty (and orphan) sections
            // omitted — mirroring the deck-detail grouping.
            if usesSections {
                for name in deck.sectionOrder + [""] {
                    if let s = bySection[name], s.totalCards > 0 { insights.sections.append(s) }
                }
            }
        }
        insights.dueForecast = forecast
        return insights
    }
}
