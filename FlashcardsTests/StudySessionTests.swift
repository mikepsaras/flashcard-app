import Testing
import Foundation
import SwiftData
@testable import Flashcards

/// A class suite so the in-memory `ModelContainer` lives for the whole test
/// (a local container would be deallocated, invalidating the model instances).
@MainActor
final class StudySessionTests {
    let container = DeckStore.makeContainer()

    /// Inserts a deck of `n` cards into the suite's container and returns them in order.
    private func makeCards(_ n: Int) -> [Card] {
        let context = container.mainContext
        let deck = Deck(name: "Test")
        context.insert(deck)
        var cards: [Card] = []
        for i in 0..<n {
            let card = Card(term: "term \(i)", definition: "def \(i)", deck: deck)
            context.insert(card)
            cards.append(card)
        }
        try? context.save()
        return cards
    }

    @Test func gradingAdvancesAndTallies() {
        let session = StudySession(cards: makeCards(3), trackLearning: true)
        #expect(session.total == 3)
        #expect(session.position == 1)

        session.grade(known: true)
        #expect(session.correctCount == 1)
        #expect(session.answered == 1)

        session.grade(known: false)        // a miss still advances (single pass)
        #expect(session.wrongCount == 1)
        #expect(session.total == 3)        // the queue never grows

        session.grade(known: true)
        #expect(session.isFinished)        // three grades ⇒ done
        #expect(session.correctCount == 2)
        #expect(session.wrongCount == 1)
    }

    @Test func missAdvancesProgressAndSchedulesSooner() {
        let cards = makeCards(1)
        let card = cards[0]
        let dueBefore = card.dueDate

        let session = StudySession(cards: cards, trackLearning: true)
        session.grade(known: false)        // didn't know it

        #expect(session.isFinished)        // single pass: the session completes
        #expect(session.answered == 1)     // progress advanced
        #expect(card.lastReviewedAt != nil)
        #expect(card.dueDate > dueBefore)  // rescheduled (sooner) for a future session
    }

    @Test func gradeLogTracksGradesInOrderForProgressColors() {
        let session = StudySession(cards: makeCards(3), trackLearning: false)
        #expect(session.gradeLog.isEmpty)

        session.grade(.again)
        session.grade(.good)
        #expect(session.gradeLog == [.again, .good])

        session.undo()
        #expect(session.gradeLog == [.again])   // stays in sync with undo
    }

    @Test func trackingPersistsScheduleChange() {
        let cards = makeCards(1)
        let card = cards[0]
        let dueBefore = card.dueDate

        let session = StudySession(cards: cards, trackLearning: true)
        session.grade(known: true)               // good ⇒ interval 1 ⇒ due advances

        #expect(card.dueDate > dueBefore)
        #expect(card.repetitions == 1)
        #expect(card.lastReviewedAt != nil)
    }

    @Test func notTrackingLeavesCardUntouched() {
        let cards = makeCards(1)
        let card = cards[0]
        let dueBefore = card.dueDate

        let session = StudySession(cards: cards, trackLearning: false)
        session.grade(known: true)

        #expect(card.dueDate == dueBefore)       // schedule unchanged
        #expect(card.repetitions == 0)
        #expect(card.lastReviewedAt == nil)
        #expect(session.correctCount == 1)       // but the session still tallies
    }

    @Test func undoRestoresCountsIndexAndSchedule() {
        let cards = makeCards(2)
        let card0 = cards[0]
        let dueBefore = card0.dueDate
        let modifiedBefore = card0.modifiedAt

        let session = StudySession(cards: cards, trackLearning: true)
        session.grade(known: true)
        #expect(session.answered == 1)
        #expect(card0.dueDate != dueBefore)

        session.undo()
        #expect(session.answered == 0)
        #expect(session.correctCount == 0)
        #expect(card0.dueDate == dueBefore)      // schedule restored exactly
        #expect(card0.repetitions == 0)
        #expect(card0.lastReviewedAt == nil)
        #expect(card0.modifiedAt == modifiedBefore)   // and modifiedAt isn't left bumped
        #expect(session.canUndo == false)
    }

    @Test func flipTogglesFace() {
        let session = StudySession(cards: makeCards(1), trackLearning: true)
        #expect(session.isShowingDefinition == false)
        session.flip()
        #expect(session.isShowingDefinition == true)
    }

    @Test func shuffleKeepsSameCardSet() {
        let cards = makeCards(8)
        let session = StudySession(cards: cards, trackLearning: true)
        let idsBefore = Set(session.items.map(\.id))
        session.shuffleRemaining()
        #expect(Set(session.items.map(\.id)) == idsBefore)
        #expect(session.items.count == 8)
    }

    @Test func reverseDirectionSchedulesIndependently() {
        let card = makeCards(1)[0]
        let forwardDueBefore = card.dueDate

        let session = StudySession(items: [ReviewItem(card: card, direction: .reverse)], trackLearning: true)
        session.grade(known: true)

        // Reverse direction advanced...
        #expect(card.reverseRepetitions == 1)
        #expect(card.reverseLastReviewedAt != nil)
        #expect(card.reverseDueDate > forwardDueBefore)
        // ...forward direction untouched.
        #expect(card.repetitions == 0)
        #expect(card.lastReviewedAt == nil)
        #expect(card.dueDate == forwardDueBefore)
    }

    /// Exercises the SwiftData #Predicate used by the Today queue at runtime
    /// (predicates compile fine but can throw when fetched if unsupported).
    @Test func todayDuePredicateFetchesDueCards() throws {
        _ = makeCards(5)   // seeded cards default to dueDate == .now (due)
        let now = Date.now
        let descriptor = FetchDescriptor<Card>(predicate: #Predicate { $0.dueDate <= now })
        let due = try container.mainContext.fetch(descriptor)
        #expect(due.count == 5)
    }
}
