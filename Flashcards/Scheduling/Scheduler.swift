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

/// Which scheduling algorithm a deck uses, backed by `Deck.schedulerRaw`. New decks default to FSRS
/// (validated against py-fsrs 6.3.1 — see `FSRS`); existing decks stay on SM-2 until opted in.
enum SchedulerKind: String, CaseIterable, Identifiable, Sendable {
    case sm2, fsrs
    var id: String { rawValue }
    var title: String {
        switch self {
        case .sm2:  "SM-2 (classic)"
        case .fsrs: "FSRS"
        }
    }
    var scheduler: Scheduler {
        switch self {
        case .sm2:  SM2Scheduler()
        case .fsrs: FSRSScheduler(weights: FSRSWeights.current())
        }
    }
}

/// Persisted per-user FSRS weights (S2.7). Unset ⇒ the validated defaults; an optimization run
/// (Settings → "Tune FSRS to my reviews", via `FSRSOptimizer`) stores a 21-element array. Stored as
/// JSON in `UserDefaults` so it travels with the app's settings, not a deck file.
enum FSRSWeights {
    static let defaultsKey = "fsrsCustomWeights"

    /// The weights the FSRS scheduler should use — the stored personalized set, or the defaults.
    static func current(_ defaults: UserDefaults = .standard) -> [Double] {
        guard let data = defaults.data(forKey: defaultsKey),
              let weights = try? JSONDecoder().decode([Double].self, from: data),
              weights.count == FSRS.defaultWeights.count
        else { return FSRS.defaultWeights }
        return weights
    }

    static func isCustomized(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.data(forKey: defaultsKey) != nil
    }

    /// Stores (or, with `nil`, clears) the personalized weights. A wrong-length array is ignored.
    static func set(_ weights: [Double]?, defaults: UserDefaults = .standard) {
        if let weights, weights.count == FSRS.defaultWeights.count,
           let data = try? JSONEncoder().encode(weights) {
            defaults.set(data, forKey: defaultsKey)
        } else {
            defaults.removeObject(forKey: defaultsKey)
        }
    }
}
