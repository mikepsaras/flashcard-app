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
        let cards = makeCards(2)           // a non-last card, so the re-look has room to be spaced
        let card = cards[0]
        let dueBefore = card.dueDate

        let session = StudySession(cards: cards, trackLearning: true)
        session.grade(known: false)        // miss card 0

        #expect(session.isFinished == false)   // the card returns for another look this session
        #expect(session.total == 3)            // queue grew by one (the requeued copy)
        #expect(session.answered == 1)         // progress advanced past the first look
        #expect(card.lastReviewedAt != nil)
        #expect(card.dueDate > dueBefore)      // and it's rescheduled (sooner) for a future day

        session.grade(known: true)         // card 1
        session.grade(known: true)         // card 0's re-look — pass it
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

    @Test func sessionUsesTheDecksScheduler() {
        // A due card gets FSRS memory state when graded — proving the session resolves the deck's
        // scheduler and applies it (a never-scheduled card starts at stability 0).
        let context = container.mainContext
        let deck = Deck(name: "FSRS")
        context.insert(deck)
        let card = Card(term: "a", definition: "b", deck: deck)   // new + due
        context.insert(card)
        try? context.save()

        let session = StudySession(cards: [card], trackLearning: true)
        session.grade(known: true)
        #expect(card.stability > 0)
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

    @Test func lastCardMissDoesNotRequeueImmediately() {
        // The in-session re-look exists to SPACE a missed card behind a few others. The last card has
        // nothing to interleave with, so missing it must NOT loop the same card back-to-back — it ends
        // the run (the lapse is already rescheduled for a future day).
        let session = StudySession(cards: makeCards(1), trackLearning: true)
        session.grade(known: false)
        #expect(session.total == 1)        // no requeued copy appended
        #expect(session.isFinished)        // ended instead of re-showing the same card
    }

    @Test func missRequeuesWithRoomThenStopsAtTheLastCard() {
        let session = StudySession(cards: makeCards(3), trackLearning: true)   // [0, 1, 2]
        session.grade(known: false)        // miss card 0 — other cards remain, so it requeues for a re-look
        #expect(session.total == 4)
        session.grade(known: true)         // card 1
        session.grade(known: true)         // card 2
        session.grade(known: false)        // now on card 0's copy — the last card — so it must NOT requeue
        #expect(session.total == 4)        // queue didn't grow
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

    // MARK: New-card throttle / review priority (S0.2)

    @Test func prioritizingReviewsKeepsReviewsFirstAndCapsNew() {
        let cards = makeCards(6)
        cards[0].lastReviewedAt = .now      // two already-reviewed units…
        cards[1].lastReviewedAt = .now
        let items = cards.map { ReviewItem(card: $0, direction: .forward) }   // …then four new

        // 2 new/day, none used yet ⇒ 2 reviews + 2 new, reviews leading.
        let out = StudySession.prioritizingReviews(items, newPerDay: 2, introducedToday: 0)
        #expect(out.count == 4)
        #expect(out.prefix(2).allSatisfy { $0.card.lastReviewedAt != nil })    // reviews first
        #expect(out.dropFirst(2).allSatisfy { $0.card.lastReviewedAt == nil }) // then new

        // Quota already spent ⇒ reviews only.
        let reviewsOnly = StudySession.prioritizingReviews(items, newPerDay: 2, introducedToday: 2)
        #expect(reviewsOnly.count == 2)
        #expect(reviewsOnly.allSatisfy { $0.card.lastReviewedAt != nil })

        // 0 ⇒ unlimited new (introducedToday ignored).
        #expect(StudySession.prioritizingReviews(items, newPerDay: 0, introducedToday: 99).count == 6)
    }

    // MARK: Interleaving (S0.3)

    @Test func interleavedRoundRobinsAcrossGroupsPreservingOrder() {
        let cards = makeCards(6)
        // Groups by first appearance: A=[0,3,5], B=[1,4], C=[2].
        cards[0].section = "A"; cards[1].section = "B"; cards[2].section = "C"
        cards[3].section = "A"; cards[4].section = "B"; cards[5].section = "A"
        let items = cards.map { ReviewItem(card: $0, direction: .forward) }

        let out = StudySession.interleaved(items, by: { $0.card.section })
        // Round 0: A,B,C · round 1: A,B · round 2: A — and the most-overdue group (A) still leads.
        #expect(out.map { $0.card.section } == ["A", "B", "C", "A", "B", "A"])
    }

    @Test func prioritizingReviewsInterleavesWithinEachSegment() {
        let cards = makeCards(4)
        cards[0].lastReviewedAt = .now; cards[0].section = "X"   // reviews…
        cards[1].lastReviewedAt = .now; cards[1].section = "Y"
        cards[2].section = "X"                                   // …then new
        cards[3].section = "Y"
        let items = cards.map { ReviewItem(card: $0, direction: .forward) }

        let out = StudySession.prioritizingReviews(items, newPerDay: 0, introducedToday: 0,
                                                   interleaveBy: { $0.card.section })
        #expect(out.prefix(2).allSatisfy { $0.card.lastReviewedAt != nil })     // reviews still lead
        #expect(out.dropFirst(2).allSatisfy { $0.card.lastReviewedAt == nil })  // new after
    }

    // MARK: Leech detection (S7.4)

    @Test func againGradeCountsLapseAndUndoReversesIt() {
        let cards = makeCards(1)
        let card = cards[0]
        #expect(card.lapses == 0)

        let session = StudySession(cards: cards, trackLearning: true)
        session.grade(.again)              // a failed recall in a real, tracked run is a lapse
        #expect(card.lapses == 1)

        session.undo()
        #expect(card.lapses == 0)          // undo reverses the lapse exactly
    }

    @Test func correctGradesDoNotCountLapses() {
        let cards = makeCards(2)
        let session = StudySession(cards: cards, trackLearning: true)
        session.grade(.good)               // a pass
        session.grade(.hard)               // Hard is q=3 — still a pass, not a lapse
        #expect(cards[0].lapses == 0)
        #expect(cards[1].lapses == 0)
    }

    @Test func practiceRunDoesNotCountLapses() {
        // Nothing due ⇒ practice; schedules (and the lapse counter) are left untouched, so drilling
        // a future-due card by missing it can't inflate its leech count.
        let context = container.mainContext
        let deck = Deck(name: "Practice"); context.insert(deck)
        let card = Card(term: "a", definition: "b", deck: deck, dueDate: .now.addingTimeInterval(5 * 86_400))
        context.insert(card)
        try? context.save()

        let session = StudySession(cards: [card], trackLearning: true)
        #expect(session.isPractice)
        session.grade(.again)
        #expect(card.lapses == 0)
    }

    @Test func notTrackingDoesNotCountLapses() {
        let cards = makeCards(1)
        let card = cards[0]
        let session = StudySession(cards: cards, trackLearning: false)
        session.grade(.again)
        #expect(card.lapses == 0)          // gated like rescheduling — no tracking, no lapse
    }

    @Test func repeatedMissesCrossTheLeechThreshold() {
        let card = makeCards(1)[0]
        #expect(card.isLeech == false)
        // A card you keep failing day after day crosses the leech line. Reset the due date each round
        // so the run is a real (tracked, non-practice) one — a miss pushes the card to tomorrow.
        for _ in 0..<Card.leechThreshold {
            card.dueDate = .now
            let session = StudySession(cards: [card], trackLearning: true)
            session.grade(.again)
        }
        #expect(card.lapses == Card.leechThreshold)
        #expect(card.isLeech)
    }

    @Test func suspendedCardExcludedFromStudyQueues() {
        let context = container.mainContext
        let deck = Deck(name: "Leechy"); context.insert(deck)
        let active = Card(term: "a", definition: "b", deck: deck)
        let parked = Card(term: "c", definition: "d", deck: deck)
        parked.suspended = true
        context.insert(active); context.insert(parked)
        try? context.save()

        // The suspended card is held out of every queue derived from allReviewItems.
        #expect(deck.allReviewItems.count == 1)
        #expect(deck.allReviewItems.first?.card.id == active.id)
        #expect(deck.dueReviewItems.allSatisfy { $0.card.id == active.id })
        #expect(deck.dueCount == 1)
    }

    // MARK: Sibling burying (S3.4)

    /// True when no two neighbors in the queue come from the same card (forward+reverse, or a
    /// requeued copy) — the user-visible guarantee of sibling burying.
    private func noAdjacentSiblings(_ items: [ReviewItem]) -> Bool {
        zip(items, items.dropFirst()).allSatisfy { $0.card.id != $1.card.id }
    }

    @Test func buryingSiblingsSeparatesForwardAndReverseOfSameCard() {
        // Born adjacent, the way `Deck.allReviewItems` emits them: [c0_f, c0_r, c1_f, c1_r, …].
        let cards = makeCards(6)
        let items = cards.flatMap {
            [ReviewItem(card: $0, direction: .forward), ReviewItem(card: $0, direction: .reverse)]
        }
        #expect(noAdjacentSiblings(items) == false)   // clustered before burying

        let out = StudySession.buryingSiblings(items, minGap: 3)
        #expect(out.count == items.count)                       // nothing lost or duplicated
        #expect(Set(out.map(\.id)) == Set(items.map(\.id)))
        #expect(noAdjacentSiblings(out))                        // siblings pulled apart
    }

    @Test func buryingSiblingsIsNoOpWhenEveryCardAppearsOnce() {
        // The common forward-only case: distinct cards, nothing to bury — order is preserved exactly,
        // so the interleave/priority ordering upstream is never disturbed.
        let items = forwardItems(5)
        let out = StudySession.buryingSiblings(items, minGap: 3)
        #expect(out.map(\.id) == items.map(\.id))
    }

    @Test func buryingSiblingsKeepsAllItemsWhenTooShortToSeparate() {
        // Two units of one card and nothing to wedge between them — can't separate, but never drops one.
        let card = makeCards(1)[0]
        let items = [ReviewItem(card: card, direction: .forward), ReviewItem(card: card, direction: .reverse)]
        let out = StudySession.buryingSiblings(items, minGap: 3)
        #expect(out.count == 2)
        #expect(Set(out.map(\.id)) == Set(items.map(\.id)))
    }

    @Test func missedCardRequeueAvoidsLandingNextToItsSibling() {
        // A's forward unit is missed; its natural requeue slot is exactly where A's reverse sits, so
        // the copy is nudged past it rather than landing back-to-back with its sibling.
        let cards = makeCards(5)
        let a = cards[0]
        let items: [ReviewItem] = [
            ReviewItem(card: a, direction: .forward),          // 0 — graded, missed
            ReviewItem(card: cards[1], direction: .forward),   // 1
            ReviewItem(card: cards[2], direction: .forward),   // 2
            ReviewItem(card: cards[3], direction: .forward),   // 3
            ReviewItem(card: a, direction: .reverse),          // 4 — sibling at the natural requeue spot
            ReviewItem(card: cards[4], direction: .forward),   // 5
        ]
        let session = StudySession(items: items, trackLearning: true)
        #expect(session.isPractice == false)        // due cards ⇒ a real run, so a miss requeues
        session.grade(known: false)                 // miss A-forward

        #expect(session.total == 7)                 // the copy was inserted…
        #expect(noAdjacentSiblings(session.items))  // …but not adjacent to A-reverse
    }
}
