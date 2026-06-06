import Testing
import Foundation
import SwiftData
@testable import Flashcards

/// A class suite so the in-memory `ModelContainer` outlives each test (model instances dangle
/// otherwise). Stats-touching cases use an isolated `UserDefaults` suite so they never clear the
/// test host's real `.standard` study history.
@MainActor
final class DeveloperToolsTests {
    let container = DeckStore.makeContainer()
    var context: ModelContext { container.mainContext }

    @Test func loadSampleLibraryTagsEveryDeckTestData() {
        let r = DeveloperTools.loadSampleLibrary(into: context)
        try? context.save()
        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        #expect(decks.count == r.decks)
        #expect(decks.allSatisfy { $0.section == DeveloperTools.testSection })   // never touches real decks
        // The sample set covers the full feature spread.
        #expect(decks.contains { !$0.sectionOrder.isEmpty })   // within-deck card sections
        #expect(decks.contains { $0.studyReversed })           // reverse study
        #expect(decks.contains { $0.cardArray.isEmpty })       // an empty deck
        let cards = decks.flatMap { $0.cardArray }
        #expect(cards.contains { $0.hasBeenReviewed })         // learning/mature/due
        #expect(cards.contains { !$0.hasBeenReviewed })        // new
    }

    @Test func stressTestGeneratesRequestedVolume() {
        let r = DeveloperTools.stressTest(decks: 4, cardsPerDeck: 25, into: context)
        try? context.save()
        #expect(r.decks == 4)
        #expect(r.cards == 100)
        let decks = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        #expect(decks.count == 4)
        #expect(decks.allSatisfy { $0.section == DeveloperTools.testSection })
        #expect(decks.flatMap { $0.cardArray }.count == 100)
    }

    @Test func removeAllTestDataDeletesOnlyTaggedDecks() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // A real deck (any other section) the dev tools must leave alone.
        let real = Deck(name: "My Real Deck", section: "Languages")
        context.insert(real)
        context.insert(Card(term: "a", definition: "b", deck: real))
        DeveloperTools.loadSampleLibrary(into: context)
        try? context.save()

        let removed = DeveloperTools.removeAllTestData(into: context, defaults: defaults)
        try? context.save()
        #expect(removed > 0)
        let remaining = (try? context.fetch(FetchDescriptor<Deck>())) ?? []
        #expect(remaining.count == 1)
        #expect(remaining.first?.name == "My Real Deck")
    }

    @Test func historyLogsAreConsistentAndWithinRange() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cal = Calendar(identifier: .gregorian)
        let logs = DeveloperTools.historyLogs(days: 365, now: now, calendar: cal)
        #expect(!logs.reviews.isEmpty)
        // Per day: correct ≤ reviews, mature ≤ reviews, matureCorrect ≤ mature.
        for (day, n) in logs.reviews {
            #expect((logs.correct[day] ?? 0) <= n)
            #expect((logs.mature[day] ?? 0) <= n)
            #expect((logs.matureCorrect[day] ?? 0) <= (logs.mature[day] ?? 0))
        }
        // Every key falls inside the requested window (today back to 364 days ago); day-keys sort
        // lexicographically == chronologically.
        let oldest = StudyStats.dayKey(cal.date(byAdding: .day, value: -364, to: now)!, calendar: cal)
        let newest = StudyStats.dayKey(now, calendar: cal)
        #expect(logs.reviews.keys.allSatisfy { $0 >= oldest && $0 <= newest })
    }

    @Test func seedReviewHistoryWritesAllFourLogs() {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        DeveloperTools.seedReviewHistory(days: 200, defaults: defaults)
        #expect(!StudyStats.reviewsByDay(defaults: defaults).isEmpty)
        #expect(!StudyStats.correctByDay(defaults: defaults).isEmpty)
        #expect(!StudyStats.matureReviewsByDay(defaults: defaults).isEmpty)
        #expect(!StudyStats.matureCorrectByDay(defaults: defaults).isEmpty)
    }

    // MARK: Phase 0 testing foundation

    @Test func phase0ScenarioBuildsObservableDecks() {
        let r = DeveloperTools.loadPhase0Scenario(into: context)
        try? context.save()
        #expect(r.decks == 3)
        let decks = ((try? context.fetch(FetchDescriptor<Deck>())) ?? []).filter { $0.section == DeveloperTools.testSection }

        // New Flood (S0.2): 60 cards, all new (never reviewed) so the throttle applies.
        let flood = decks.first { $0.name.contains("New Flood") }!
        #expect(flood.cardArray.count == 60)
        #expect(flood.cardArray.allSatisfy { $0.lastReviewedAt == nil })

        // Interleave Demo (S0.3): three sections, every card due.
        let interleave = decks.first { $0.name.contains("Interleave") }!
        #expect(Set(interleave.cardArray.map(\.section)) == ["Alpha", "Beta", "Gamma"])
        #expect(interleave.cardArray.allSatisfy { $0.isDue(.forward) && $0.lastReviewedAt != nil })

        // Miss & Requeue (S0.1): a handful of due, already-reviewed cards (a real, non-practice run).
        let requeue = decks.first { $0.name.contains("Requeue") }!
        #expect(requeue.cardArray.count == 8)
        #expect(requeue.cardArray.allSatisfy { $0.isDue(.forward) })
    }

    @Test func sampleLinterCardsTriggerEveryWarning() {
        let kinds = Set(CardQualityLinter.warnings(for: DeveloperTools.sampleCardsWithIssues()).values.flatMap { $0 })
        #expect(kinds.contains(.circular))
        #expect(kinds.contains(.enumeration))
        #expect(kinds.contains(.longAnswer))
        #expect(kinds.contains(.shortAnswer))
        #expect(kinds.contains(.duplicate))
    }
}
