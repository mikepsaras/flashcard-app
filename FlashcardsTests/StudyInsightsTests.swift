import Testing
import Foundation
import SwiftData
@testable import Flashcards

/// A class suite so the in-memory `ModelContainer` outlives each test (model instances
/// would dangle otherwise).
@MainActor
final class StudyInsightsTests {
    let container = DeckStore.makeContainer()
    let cal = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeDeck(studyReversed: Bool = false) -> Deck {
        let deck = Deck(name: "T", studyReversed: studyReversed)
        container.mainContext.insert(deck)
        return deck
    }

    @discardableResult
    private func addCard(to deck: Deck, reviewed: Bool, interval: Int = 0, reverseInterval: Int = 0, due: Date? = nil) -> Card {
        let card = Card(term: "t", definition: "d", deck: deck, dueDate: due ?? now)
        if reviewed {
            card.lastReviewedAt = now
            card.repetitions = 1
            card.interval = interval
        }
        card.reverseInterval = reverseInterval
        if reverseInterval > 0 { card.reverseLastReviewedAt = now }
        container.mainContext.insert(card)
        return card
    }

    private func key(_ offset: Int) -> String {
        StudyStats.dayKey(cal.date(byAdding: .day, value: offset, to: now)!, calendar: cal)
    }

    @Test func compositionBucketsByMaturity() {
        let deck = makeDeck()
        addCard(to: deck, reviewed: false)               // New
        addCard(to: deck, reviewed: true, interval: 5)   // Learning (< 21)
        addCard(to: deck, reviewed: true, interval: 40)  // Mature (>= 21)
        let s = StudyInsights.make(decks: [deck], reviewsByDay: [:], correctByDay: [:], now: now, calendar: cal)
        #expect(s.totalCards == 3)
        #expect(s.newCount == 1)
        #expect(s.learningCount == 1)
        #expect(s.matureCount == 1)
    }

    @Test func reverseIntervalCountsTowardMaturityWhenStudyReversed() {
        let deck = makeDeck(studyReversed: true)
        // Forward interval short, reverse interval mature ⇒ counts as Mature.
        addCard(to: deck, reviewed: true, interval: 3, reverseInterval: 30)
        let s = StudyInsights.make(decks: [deck], reviewsByDay: [:], correctByDay: [:], now: now, calendar: cal)
        #expect(s.matureCount == 1)
        #expect(s.learningCount == 0)
    }

    @Test func reverseEarnedMaturityCountsEvenWhenReverseDisabled() {
        // A card matured on the reverse side, then reverse study turned OFF, must still count as
        // Mature (not demoted to Learning) — maturity reflects what was learned, not the toggle.
        let deck = makeDeck(studyReversed: false)
        addCard(to: deck, reviewed: false, reverseInterval: 30)
        let s = StudyInsights.make(decks: [deck], reviewsByDay: [:], correctByDay: [:], now: now, calendar: cal)
        #expect(s.newCount == 0)
        #expect(s.learningCount == 0)
        #expect(s.matureCount == 1)
    }

    @Test func accuracyIsCorrectOverReviewsAndNilWhenEmpty() {
        let deck = makeDeck()
        let reviews = [key(0): 2, key(-1): 2]   // 4 total
        let correct = [key(0): 1, key(-1): 2]   // 3 correct ⇒ 0.75
        let s = StudyInsights.make(decks: [deck], reviewsByDay: reviews, correctByDay: correct, now: now, calendar: cal)
        #expect(s.reviewsAllTime == 4)
        #expect(s.accuracyAllTime == 0.75)
        #expect(s.correctAllTime == 3)
        let empty = StudyInsights.make(decks: [deck], reviewsByDay: [:], correctByDay: [:], now: now, calendar: cal)
        #expect(empty.accuracyAllTime == nil)
    }

    @Test func dailyAverageOverActiveDays() {
        let deck = makeDeck()
        let reviews = [key(0): 10, key(-1): 20, key(-5): 0]   // 2 active days, 30 total
        let s = StudyInsights.make(decks: [deck], reviewsByDay: reviews, correctByDay: [:], now: now, calendar: cal)
        #expect(s.dailyAverage == 15)
    }

    @Test func streaksComeFromReviewLog() {
        let deck = makeDeck()
        let reviews = [key(0): 1, key(-1): 1, key(-2): 1, key(-5): 1]   // run of 3 ending today, plus a lone day
        let s = StudyInsights.make(decks: [deck], reviewsByDay: reviews, correctByDay: [:], now: now, calendar: cal)
        #expect(s.currentStreak == 3)
        #expect(s.longestStreak == 3)
    }

    @Test func dueWindowsCountReviewItems() {
        let deck = makeDeck()
        addCard(to: deck, reviewed: true, interval: 1, due: now.addingTimeInterval(-86_400))      // overdue
        addCard(to: deck, reviewed: true, interval: 3, due: now.addingTimeInterval(3 * 86_400))    // due in 3 days
        addCard(to: deck, reviewed: true, interval: 30, due: now.addingTimeInterval(30 * 86_400))  // far future
        let s = StudyInsights.make(decks: [deck], reviewsByDay: [:], correctByDay: [:], now: now, calendar: cal)
        #expect(s.dueNow == 1)
        #expect(s.dueThisWeek == 2)   // overdue + due-in-3-days
    }

    @Test func dueForecastBucketsByDayWithOverdueFoldedIntoToday() {
        let deck = makeDeck()
        addCard(to: deck, reviewed: true, interval: 1, due: now.addingTimeInterval(-86_400))      // overdue → today
        addCard(to: deck, reviewed: true, interval: 1, due: now)                                   // today
        addCard(to: deck, reviewed: true, interval: 3, due: now.addingTimeInterval(3 * 86_400))    // +3 days
        addCard(to: deck, reviewed: true, interval: 30, due: now.addingTimeInterval(30 * 86_400))  // beyond the window
        let s = StudyInsights.make(decks: [deck], reviewsByDay: [:], correctByDay: [:], now: now, calendar: cal)
        #expect(s.dueForecast.count == StudyInsights.forecastDays)
        #expect(s.dueForecast[0] == 2)              // overdue + today
        #expect(s.dueForecast[3] == 1)              // due in 3 days
        #expect(s.dueForecast.reduce(0, +) == 3)    // the 30-day-out card falls outside the 14-day window
    }

    @Test func perDeckBreakdownCountsEachDeck() {
        let a = makeDeck(); a.name = "A"
        addCard(to: a, reviewed: false, due: now.addingTimeInterval(10 * 86_400))                  // new, not due
        addCard(to: a, reviewed: true, interval: 40, due: now.addingTimeInterval(40 * 86_400))     // mature, not due
        let b = makeDeck(); b.name = "B"
        addCard(to: b, reviewed: true, interval: 5, due: now.addingTimeInterval(-86_400))          // learning + overdue
        let s = StudyInsights.make(decks: [a, b], reviewsByDay: [:], correctByDay: [:], now: now, calendar: cal)
        #expect(s.perDeck.count == 2)
        let statA = s.perDeck.first { $0.name == "A" }!
        #expect(statA.totalCards == 2)
        #expect(statA.newCount == 1)
        #expect(statA.matureCount == 1)
        #expect(statA.due == 0)
        let statB = s.perDeck.first { $0.name == "B" }!
        #expect(statB.learningCount == 1)
        #expect(statB.due == 1)
    }

    @Test func lastWeekTrendFromPriorSevenDays() {
        let deck = makeDeck()
        let reviews = [key(0): 5, key(-3): 5, key(-8): 4, key(-10): 6]   // this week 10, last week 10
        let correct = [key(0): 5, key(-3): 4, key(-8): 2, key(-10): 6]   // this 9/10, last 8/10
        let s = StudyInsights.make(decks: [deck], reviewsByDay: reviews, correctByDay: correct, now: now, calendar: cal)
        #expect(s.reviewsThisWeek == 10)
        #expect(s.reviewsLastWeek == 10)
        #expect(s.accuracyThisWeek == 0.9)
        #expect(s.accuracyLastWeek == 0.8)
    }
}
