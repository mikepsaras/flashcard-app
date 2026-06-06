import Foundation

/// Bridges the pure SM-2 algorithm to the SwiftData `Card` model, per direction.
extension Card {
    /// Current scheduling state for a direction, extracted as a pure value.
    func schedulingState(_ direction: ReviewDirection = .forward) -> SchedulingState {
        switch direction {
        case .forward:
            SchedulingState(easeFactor: easeFactor, interval: interval, repetitions: repetitions, dueDate: dueDate,
                            stability: stability, difficulty: difficulty, lastReviewedAt: lastReviewedAt)
        case .reverse:
            SchedulingState(easeFactor: reverseEaseFactor, interval: reverseInterval, repetitions: reverseRepetitions, dueDate: reverseDueDate,
                            stability: reverseStability, difficulty: reverseDifficulty, lastReviewedAt: reverseLastReviewedAt)
        }
    }

    func dueDate(_ direction: ReviewDirection) -> Date {
        direction == .forward ? dueDate : reverseDueDate
    }

    func isDue(_ direction: ReviewDirection, now: Date = .now) -> Bool {
        dueDate(direction) <= now
    }

    func lastReviewedAt(_ direction: ReviewDirection) -> Date? {
        direction == .forward ? lastReviewedAt : reverseLastReviewedAt
    }

    /// Writes an SM-2 result back onto the card for a direction.
    func apply(_ state: SchedulingState, direction: ReviewDirection = .forward, reviewedAt: Date = .now) {
        switch direction {
        case .forward:
            easeFactor = state.easeFactor
            interval = state.interval
            repetitions = state.repetitions
            dueDate = state.dueDate
            stability = state.stability
            difficulty = state.difficulty
            lastReviewedAt = reviewedAt
        case .reverse:
            reverseEaseFactor = state.easeFactor
            reverseInterval = state.interval
            reverseRepetitions = state.repetitions
            reverseDueDate = state.dueDate
            reverseStability = state.stability
            reverseDifficulty = state.difficulty
            reverseLastReviewedAt = reviewedAt
        }
        modifiedAt = reviewedAt
    }

    /// Restores a direction's state exactly (used by study undo), including the prior
    /// `lastReviewedAt`/`modifiedAt` rather than stamping "now".
    func restore(_ state: SchedulingState, direction: ReviewDirection, lastReviewedAt: Date?, modifiedAt: Date) {
        switch direction {
        case .forward:
            easeFactor = state.easeFactor
            interval = state.interval
            repetitions = state.repetitions
            dueDate = state.dueDate
            stability = state.stability
            difficulty = state.difficulty
            self.lastReviewedAt = lastReviewedAt
        case .reverse:
            reverseEaseFactor = state.easeFactor
            reverseInterval = state.interval
            reverseRepetitions = state.repetitions
            reverseDueDate = state.dueDate
            reverseStability = state.stability
            reverseDifficulty = state.difficulty
            reverseLastReviewedAt = lastReviewedAt
        }
        self.modifiedAt = modifiedAt
    }

    /// Resets both directions' schedules to brand-new (used by "reset progress").
    func resetSchedule(now: Date = .now) {
        apply(.initial(now: now), direction: .forward, reviewedAt: now)
        apply(.initial(now: now), direction: .reverse, reviewedAt: now)
        lastReviewedAt = nil
        reverseLastReviewedAt = nil
    }
}
