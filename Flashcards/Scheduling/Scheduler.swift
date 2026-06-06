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

/// Which scheduling algorithm a deck uses, backed by `Deck.schedulerRaw`. SM-2 is the default; FSRS is
/// opt-in per deck (beta) until it's validated against the upstream reference (see `FSRS`).
enum SchedulerKind: String, CaseIterable, Identifiable, Sendable {
    case sm2, fsrs
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sm2:  "SM-2 (classic)"
        case .fsrs: "FSRS (beta)"
        }
    }
    var scheduler: Scheduler {
        switch self {
        case .sm2:  SM2Scheduler()
        case .fsrs: FSRSScheduler()
        }
    }
}
