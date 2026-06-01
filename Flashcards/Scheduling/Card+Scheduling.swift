import Foundation

/// Bridges the pure SM-2 algorithm to the SwiftData `Card` model.
extension Card {
    /// Current scheduling state, extracted as a pure value.
    var schedulingState: SchedulingState {
        SchedulingState(
            easeFactor: easeFactor,
            interval: interval,
            repetitions: repetitions,
            dueDate: dueDate
        )
    }

    /// Writes an SM-2 result back onto the card.
    func apply(_ state: SchedulingState, reviewedAt: Date = .now) {
        easeFactor = state.easeFactor
        interval = state.interval
        repetitions = state.repetitions
        dueDate = state.dueDate
        lastReviewedAt = reviewedAt
        modifiedAt = reviewedAt
    }

    /// Resets the card's schedule to brand-new (used by "reset progress").
    func resetSchedule(now: Date = .now) {
        apply(.initial(now: now), reviewedAt: now)
        lastReviewedAt = nil
    }
}
