import Foundation

/// Abstraction over a spaced-repetition algorithm, so the study engine can swap or select schedulers
/// (SM-2 today; FSRS in Phase 2, chosen per deck in S2.4) without changing its call sites. Pure value
/// semantics — inject `now`/`calendar` for repeatable tests, exactly like `SM2`.
protocol Scheduler: Sendable {
    /// The next scheduling state for a card after grading it `grade` at `now`.
    func schedule(current: SchedulingState, grade: Grade, now: Date, calendar: Calendar) -> SchedulingState
}

extension Scheduler {
    /// Convenience with the usual defaults (mirrors `SM2.schedule`'s defaulted parameters).
    func schedule(current: SchedulingState, grade: Grade, now: Date = .now) -> SchedulingState {
        schedule(current: current, grade: grade, now: now, calendar: .current)
    }
}

/// The canonical SuperMemo-2 scheduler, delegating to the pure `SM2` algorithm. The default scheduler
/// until FSRS lands; kept as a selectable conformer thereafter for back-compat and A/B.
struct SM2Scheduler: Scheduler {
    func schedule(current: SchedulingState, grade: Grade, now: Date, calendar: Calendar) -> SchedulingState {
        SM2.schedule(current: current, grade: grade, now: now, calendar: calendar)
    }
}
