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

        // Library composition, due windows, per-deck breakdown, and the due forecast.
        let weekAhead = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        let startToday = calendar.startOfDay(for: now)
        var forecast = Array(repeating: 0, count: forecastDays)
        for deck in decks {
            var stat = DeckStat(id: deck.id, name: deck.displayName, colorHex: deck.colorHex,
                                totalCards: 0, due: 0, newCount: 0, learningCount: 0, matureCount: 0)
            for card in deck.cardArray {
                insights.totalCards += 1
                stat.totalCards += 1
                if !card.hasBeenReviewed {
                    insights.newCount += 1; stat.newCount += 1
                } else {
                    // Best interval the card earned in any direction — independent of the deck's
                    // current `studyReversed` toggle.
                    let interval = max(card.interval, card.reverseInterval)
                    if interval >= matureIntervalDays { insights.matureCount += 1; stat.matureCount += 1 }
                    else { insights.learningCount += 1; stat.learningCount += 1 }
                }
            }
            for item in deck.allReviewItems {
                if item.dueDate <= now { insights.dueNow += 1; stat.due += 1 }
                if item.dueDate <= weekAhead { insights.dueThisWeek += 1 }
                // Bucket into the forecast; overdue folds into today (index 0).
                let dueDay = calendar.startOfDay(for: item.dueDate)
                let offset = max(0, calendar.dateComponents([.day], from: startToday, to: dueDay).day ?? 0)
                if offset < forecastDays { forecast[offset] += 1 }
            }
            insights.perDeck.append(stat)
        }
        insights.dueForecast = forecast
        insights.sections = sectionStats(decks: decks, now: now)
        return insights
    }

    /// Per-section composition for decks that use sections (`sectionOrder` non-empty). Sections are
    /// listed in the deck's own order, unsectioned cards last; sections with no cards are omitted.
    @MainActor
    private static func sectionStats(decks: [Deck], now: Date) -> [SectionStat] {
        var result: [SectionStat] = []
        for deck in decks where !deck.sectionOrder.isEmpty {
            // Capture the deck's scalar fields (not the @Model itself) so the accumulator never has
            // to "send" the non-Sendable Deck across isolation (Swift 6 strict concurrency, which the
            // Release config flags even where Debug doesn't).
            let deckID = deck.id.uuidString
            let deckName = deck.displayName
            let colorHex = deck.colorHex
            var byName: [String: SectionStat] = [:]
            func slot(_ name: String) -> SectionStat {
                byName[name] ?? SectionStat(id: "\(deckID)-\(name)", deckName: deckName, colorHex: colorHex,
                                            section: name, totalCards: 0, due: 0, newCount: 0, learningCount: 0, matureCount: 0)
            }
            for card in deck.cardArray {
                var stat = slot(card.section)
                stat.totalCards += 1
                if !card.hasBeenReviewed { stat.newCount += 1 }
                else if max(card.interval, card.reverseInterval) >= matureIntervalDays { stat.matureCount += 1 }
                else { stat.learningCount += 1 }
                byName[card.section] = stat
            }
            for item in deck.allReviewItems where item.dueDate <= now {
                var stat = slot(item.card.section)
                stat.due += 1
                byName[item.card.section] = stat
            }
            for name in deck.sectionOrder + [""] {
                if let stat = byName[name], stat.totalCards > 0 { result.append(stat) }
            }
        }
        return result
    }
}
