import Testing
import SwiftData
@testable import Flashcards

/// A class suite so the in-memory `ModelContainer` lives for the whole test
/// (a local container would be deallocated, invalidating the model instances).
@MainActor
final class StudySessionTests {
    let container = PersistenceController.makeContainer(syncEnabled: false, inMemory: true)

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

        session.grade(known: false)
        #expect(session.wrongCount == 1)

        session.grade(known: true)
        #expect(session.isFinished)
        #expect(session.correctCount == 2)
        #expect(session.wrongCount == 1)
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
        let idsBefore = Set(session.cards.map(\.id))
        session.shuffleRemaining()
        #expect(Set(session.cards.map(\.id)) == idsBefore)
        #expect(session.cards.count == 8)
    }
}
