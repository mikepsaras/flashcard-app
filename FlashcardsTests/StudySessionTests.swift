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

        session.grade(known: false)        // a miss now earns another look this session…
        #expect(session.wrongCount == 1)
        #expect(session.total == 4)        // …so the queue grows by one (a learning step)

        session.grade(known: true)             // third original card
        #expect(session.isFinished == false)   // the requeued miss still remains
        session.grade(known: true)             // …grade the requeued card
        #expect(session.isFinished)
        #expect(session.correctCount == 3)
        #expect(session.wrongCount == 1)
    }

    @Test func missReschedulesSoonerAndEarnsAnotherLookThisSession() {
        let cards = makeCards(1)
        let card = cards[0]
        let dueBefore = card.dueDate

        let session = StudySession(cards: cards, trackLearning: true)
        session.grade(known: false)        // didn't know it

        #expect(session.isFinished == false)   // the card returns for another look this session
        #expect(session.total == 2)            // queue grew by one
        #expect(session.answered == 1)         // progress advanced past the first look
        #expect(card.lastReviewedAt != nil)
        #expect(card.dueDate > dueBefore)      // and it's rescheduled (sooner) for a future day

        session.grade(known: true)         // see it again, pass it
        #expect(session.isFinished)
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

    @Test func practiceRunLeavesScheduleUntouchedButStillTallies() {
        // A card scheduled in the future (not due) — studying it is a practice pass, so
        // "Study Again" can't keep pushing its interval out.
        let context = container.mainContext
        let deck = Deck(name: "Practice"); context.insert(deck)
        let card = Card(term: "a", definition: "b", deck: deck, dueDate: .now.addingTimeInterval(5 * 86_400))
        context.insert(card)
        try? context.save()
        let dueBefore = card.dueDate

        let session = StudySession(cards: [card], trackLearning: true)
        #expect(session.isPractice)              // nothing due ⇒ practice

        session.grade(known: true)
        #expect(session.correctCount == 1)       // scoreboard still works
        #expect(card.dueDate == dueBefore)       // but the schedule is untouched
        #expect(card.repetitions == 0)
        #expect(card.lastReviewedAt == nil)
    }

    @Test func runWithDueCardsIsNotPracticeAndStillTracks() {
        let cards = makeCards(2)                  // seeded cards are due now
        let session = StudySession(cards: cards, trackLearning: true)
        #expect(session.isPractice == false)
        let dueBefore = cards[0].dueDate
        session.grade(known: true)
        #expect(cards[0].dueDate != dueBefore)   // a due card still advances normally
        #expect(cards[0].repetitions == 1)
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

    @Test func undoRestoresScheduleEvenIfTrackingToggledOffAfterGrading() {
        // Grade with tracking on, then flip "Track learning" off, then undo. The undo must
        // still fully restore the card — it must not read the live flag and skip the restore.
        let cards = makeCards(1)
        let card = cards[0]
        let dueBefore = card.dueDate
        let modifiedBefore = card.modifiedAt

        let session = StudySession(cards: cards, trackLearning: true)
        session.grade(known: true)
        #expect(card.dueDate != dueBefore)   // schedule advanced

        session.trackLearning = false        // user toggles tracking off mid-session
        session.undo()

        #expect(card.dueDate == dueBefore)   // schedule restored despite tracking now off
        #expect(card.repetitions == 0)
        #expect(card.lastReviewedAt == nil)
        #expect(card.modifiedAt == modifiedBefore)
        #expect(session.answered == 0)
    }

    @Test func flipTogglesFace() {
        let session = StudySession(cards: makeCards(1), trackLearning: true)
        #expect(session.isShowingDefinition == false)
        session.flip()
        #expect(session.isShowingDefinition == true)
    }

    @Test func shuffleAllKeepsCardSetAndRestarts() {
        let cards = makeCards(8)
        let session = StudySession(cards: cards, trackLearning: false)
        session.grade(known: true)
        session.grade(known: false)
        let idsBefore = Set(session.items.map(\.id))

        session.shuffleAll()

        #expect(Set(session.items.map(\.id)) == idsBefore)   // same cards, reordered
        #expect(session.items.count == 8)
        #expect(session.answered == 0)                        // restarts from the top
        #expect(session.correctCount == 0)
        #expect(session.wrongCount == 0)
        #expect(session.gradeLog.isEmpty)
        #expect(session.canUndo == false)                     // undo history cleared
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

    // MARK: Learning-step requeue (S0.1)

    @Test func missedCardRequeuedAtMostOncePerSession() {
        let session = StudySession(cards: makeCards(1), trackLearning: true)
        session.grade(known: false)        // miss ⇒ requeue (queue grows to 2)
        #expect(session.total == 2)
        session.grade(known: false)        // miss the requeued copy ⇒ NOT requeued again (cap 1)
        #expect(session.total == 2)
        #expect(session.isFinished)
    }

    @Test func undoRemovesTheRequeuedCopy() {
        let session = StudySession(cards: makeCards(2), trackLearning: true)
        session.grade(known: false)        // miss card 0 ⇒ requeue, total 3
        #expect(session.total == 3)
        #expect(session.wrongCount == 1)

        session.undo()
        #expect(session.total == 2)        // the requeued copy is removed
        #expect(session.wrongCount == 0)
        #expect(session.answered == 0)
        #expect(session.canUndo == false)
    }

    @Test func practiceRunDoesNotRequeueMisses() {
        let context = container.mainContext
        let deck = Deck(name: "Practice"); context.insert(deck)
        let card = Card(term: "a", definition: "b", deck: deck, dueDate: .now.addingTimeInterval(5 * 86_400))
        context.insert(card)
        try? context.save()

        let session = StudySession(cards: [card], trackLearning: true)
        #expect(session.isPractice)
        session.grade(known: false)
        #expect(session.total == 1)        // practice never grows the queue
        #expect(session.isFinished)
    }

    @Test func shuffleDropsInSessionRequeueDuplicates() {
        let session = StudySession(cards: makeCards(4), trackLearning: true)
        session.grade(known: false)        // miss ⇒ requeue, total 5
        #expect(session.total == 5)

        session.shuffleAll()
        #expect(session.total == 4)        // restart is a clean pass over the unique set
        #expect(Set(session.items.map(\.id)).count == 4)
    }

    // MARK: Session-size cap

    private func forwardItems(_ n: Int) -> [ReviewItem] {
        makeCards(n).map { ReviewItem(card: $0, direction: .forward) }
    }

    @Test func sessionCapTakesLeadingItems() {
        let items = forwardItems(5)
        let capped = StudySession.cap(items, limit: 2)
        #expect(capped.count == 2)
        #expect(capped.map(\.id) == Array(items.prefix(2)).map(\.id))   // order preserved
    }

    @Test func sessionCapZeroMeansUnlimited() {
        let items = forwardItems(4)
        #expect(StudySession.cap(items, limit: 0).count == 4)
    }

    @Test func sessionCapLargerThanCountReturnsAll() {
        let items = forwardItems(3)
        #expect(StudySession.cap(items, limit: 100).count == 3)
    }
}
