import SwiftUI

/// Drives a single study run: a fixed set of review items (cards in a direction), a
/// current position, flip state, running ✓/✕ tallies, and an exact undo stack. SM-2
/// grades are applied to each item's direction only when `trackLearning` is on.
@Observable
@MainActor
final class StudySession {
    private(set) var items: [ReviewItem]
    private(set) var index = 0
    private(set) var isShowingDefinition = false
    private(set) var correctCount = 0
    private(set) var wrongCount = 0
    /// The grade given to each answered card, in order — used to color the progress bar.
    private(set) var gradeLog: [Grade] = []
    var trackLearning: Bool
    /// A run where nothing is actually due — a pure practice pass (e.g. "Study Again" after
    /// the deck's due cards are cleared, or studying a deck ahead of schedule). Schedules are
    /// never advanced in practice, so repeating it can't inflate intervals; the ✓/✕ scoreboard
    /// still works.
    let isPractice: Bool

    /// Snapshot captured before each grade so undo can restore exactly.
    private struct Move {
        let item: ReviewItem
        let wasShowingDefinition: Bool
        let previousState: SchedulingState
        let previousReviewedAt: Date?
        let previousModifiedAt: Date
        let previousIndex: Int
        let previousCorrect: Int
        let previousWrong: Int
    }
    private var history: [Move] = []

    init(items: [ReviewItem], trackLearning: Bool, now: Date = .now) {
        self.items = items
        self.trackLearning = trackLearning
        // Nothing due ⇒ practice. Studying cards that aren't due (and advancing them) would
        // push their intervals out further with every pass, so practice leaves them alone.
        self.isPractice = !items.isEmpty && items.allSatisfy { !$0.card.isDue($0.direction, now: now) }
    }

    /// Convenience: a forward-only run (used by tests and single-direction callers).
    convenience init(cards: [Card], trackLearning: Bool) {
        self.init(items: cards.map { ReviewItem(card: $0, direction: .forward) }, trackLearning: trackLearning)
    }

    /// Applies the "cards per session" cap to a list of review items (0 ⇒ unlimited),
    /// taking the leading `limit` (callers pass them most-due first). Pure and static so
    /// it's unit-testable without the view's `@AppStorage`.
    static func cap(_ items: [ReviewItem], limit: Int) -> [ReviewItem] {
        limit > 0 ? Array(items.prefix(limit)) : items
    }

    // MARK: Derived state
    var total: Int { items.count }
    var answered: Int { index }
    var position: Int { min(index + 1, max(total, 1)) }
    var isFinished: Bool { index >= items.count }
    var current: ReviewItem? { isFinished ? nil : items[index] }
    var canUndo: Bool { !history.isEmpty }

    // MARK: Intents

    func flip() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) {
            isShowingDefinition.toggle()
        }
    }

    /// Two-button convenience: ✓ ⇒ good, ✕ ⇒ again.
    func grade(known: Bool, now: Date = .now) {
        grade(.from(known: known), now: now)
    }

    /// Grade the current item with an explicit SM-2 grade (used by 4-button mode).
    func grade(_ grade: Grade, now: Date = .now) {
        guard let item = current else { return }
        let card = item.card
        let direction = item.direction

        history.append(Move(
            item: item,
            wasShowingDefinition: isShowingDefinition,
            previousState: card.schedulingState(direction),
            previousReviewedAt: card.lastReviewedAt(direction),
            previousModifiedAt: card.modifiedAt,
            previousIndex: index,
            previousCorrect: correctCount,
            previousWrong: wrongCount
        ))

        if trackLearning && !isPractice {
            let updated = SM2.schedule(current: card.schedulingState(direction), grade: grade, now: now)
            card.apply(updated, direction: direction, reviewedAt: now)
        }

        if grade.isCorrect { correctCount += 1 } else { wrongCount += 1 }
        gradeLog.append(grade)
        advance()
    }

    @discardableResult
    func undo() -> Grade? {
        guard let move = history.popLast() else { return nil }
        let undoneGrade = gradeLog.popLast()

        // Always restore the snapshot — never gate this on the *current* `trackLearning`
        // value. If the grade applied an SM-2 change, this reverts it; if it didn't (tracking
        // was off at grade time), restoring the captured state is a no-op. Reading the live
        // flag instead would leave a card advanced when tracking is toggled off after grading.
        move.item.card.restore(
            move.previousState,
            direction: move.item.direction,
            lastReviewedAt: move.previousReviewedAt,
            modifiedAt: move.previousModifiedAt
        )

        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            index = move.previousIndex
            correctCount = move.previousCorrect
            wrongCount = move.previousWrong
            isShowingDefinition = move.wasShowingDefinition
        }
        return undoneGrade
    }

    /// Shuffles the current item and everything not yet answered. Undo history is
    /// cleared (you can't undo across a shuffle).
    func shuffleRemaining() {
        guard index < items.count else { return }
        var updated = items
        let shuffledTail = Array(updated[index...]).shuffled()
        updated.replaceSubrange(index..., with: shuffledTail)
        history.removeAll()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            items = updated
            isShowingDefinition = false
        }
    }

    private func advance() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            isShowingDefinition = false
            index += 1
        }
    }
}
