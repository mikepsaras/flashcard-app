import SwiftUI

/// Drives a single study run: a fixed set of cards, a current position, flip state,
/// running ✓/✕ tallies, and an exact undo stack. SM-2 grades are applied to the
/// cards only when `trackLearning` is on.
@Observable
@MainActor
final class StudySession {
    private(set) var cards: [Card]
    private(set) var index = 0
    private(set) var isShowingDefinition = false
    private(set) var correctCount = 0
    private(set) var wrongCount = 0
    var trackLearning: Bool

    /// Snapshot captured before each grade so undo can restore exactly.
    private struct Move {
        let card: Card
        let wasShowingDefinition: Bool
        let previousState: SchedulingState
        let previousReviewedAt: Date?
        let previousIndex: Int
        let previousCorrect: Int
        let previousWrong: Int
    }
    private var history: [Move] = []

    init(cards: [Card], trackLearning: Bool) {
        self.cards = cards
        self.trackLearning = trackLearning
    }

    // MARK: Derived state
    var total: Int { cards.count }
    var answered: Int { index }
    var position: Int { min(index + 1, max(total, 1)) }
    var isFinished: Bool { index >= cards.count }
    var current: Card? { isFinished ? nil : cards[index] }
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

    /// Grade the current card with an explicit SM-2 grade (used by 4-button mode).
    func grade(_ grade: Grade, now: Date = .now) {
        guard let card = current else { return }

        history.append(Move(
            card: card,
            wasShowingDefinition: isShowingDefinition,
            previousState: card.schedulingState,
            previousReviewedAt: card.lastReviewedAt,
            previousIndex: index,
            previousCorrect: correctCount,
            previousWrong: wrongCount
        ))

        if trackLearning {
            let updated = SM2.schedule(current: card.schedulingState, grade: grade, now: now)
            card.apply(updated, reviewedAt: now)
        }

        if grade.isCorrect { correctCount += 1 } else { wrongCount += 1 }
        advance()
    }

    func undo() {
        guard let move = history.popLast() else { return }

        if trackLearning {
            let card = move.card
            card.easeFactor = move.previousState.easeFactor
            card.interval = move.previousState.interval
            card.repetitions = move.previousState.repetitions
            card.dueDate = move.previousState.dueDate
            card.lastReviewedAt = move.previousReviewedAt
        }

        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            index = move.previousIndex
            correctCount = move.previousCorrect
            wrongCount = move.previousWrong
            isShowingDefinition = move.wasShowingDefinition
        }
    }

    /// Shuffles the current card and everything not yet answered. Undo history is
    /// cleared (you can't undo across a shuffle).
    func shuffleRemaining() {
        guard index < cards.count else { return }
        var updated = cards
        let shuffledTail = Array(updated[index...]).shuffled()
        updated.replaceSubrange(index..., with: shuffledTail)
        history.removeAll()
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            cards = updated
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
