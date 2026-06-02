import Foundation

/// A pure snapshot of study + library statistics for the Insights screen. Built from the decks
/// plus the `StudyStats` day logs; deterministic given its inputs, so the aggregation is
/// unit-tested and the view stays a dumb renderer.
struct StudyInsights: Equatable {
    var reviewsToday = 0
    var reviewsThisWeek = 0
    var reviewsAllTime = 0
    /// Mean reviews across days that had at least one review (0 when none).
    var dailyAverage = 0
    var currentStreak = 0
    var longestStreak = 0
    /// correct / reviews; `nil` when there are no reviews to divide by.
    var accuracyAllTime: Double?
    var accuracyThisWeek: Double?
    var totalCards = 0
    var newCount = 0
    var learningCount = 0
    var matureCount = 0
    var dueNow = 0
    /// Review units due within the next 7 days (includes anything overdue).
    var dueThisWeek = 0

    /// An interval ≥ this many days is considered "mature" (Anki's convention).
    static let matureIntervalDays = 21

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

        let weekKeys = Set((0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: now)
                .map { StudyStats.dayKey($0, calendar: calendar) }
        })
        insights.reviewsThisWeek = weekKeys.reduce(0) { $0 + (reviewsByDay[$1] ?? 0) }
        let correctThisWeek = weekKeys.reduce(0) { $0 + (correctByDay[$1] ?? 0) }
        let correctAllTime = correctByDay.values.reduce(0, +)

        insights.accuracyAllTime = insights.reviewsAllTime > 0
            ? Double(correctAllTime) / Double(insights.reviewsAllTime) : nil
        insights.accuracyThisWeek = insights.reviewsThisWeek > 0
            ? Double(correctThisWeek) / Double(insights.reviewsThisWeek) : nil

        let activeDays = reviewsByDay.values.filter { $0 > 0 }.count
        insights.dailyAverage = activeDays > 0
            ? Int((Double(insights.reviewsAllTime) / Double(activeDays)).rounded()) : 0

        // Library composition + due windows (from the cards).
        let weekAhead = calendar.date(byAdding: .day, value: 7, to: now) ?? now
        for deck in decks {
            for card in deck.cardArray {
                insights.totalCards += 1
                if !card.hasBeenReviewed {
                    insights.newCount += 1
                } else {
                    let interval = deck.studyReversed ? max(card.interval, card.reverseInterval) : card.interval
                    if interval >= matureIntervalDays { insights.matureCount += 1 }
                    else { insights.learningCount += 1 }
                }
            }
            for item in deck.allReviewItems {
                if item.dueDate <= now { insights.dueNow += 1 }
                if item.dueDate <= weekAhead { insights.dueThisWeek += 1 }
            }
        }
        return insights
    }
}
