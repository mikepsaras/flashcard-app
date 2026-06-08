import Foundation

/// Abstraction over a spaced-repetition algorithm — a thin seam so the study engine resolves a deck's
/// scheduler without hard-coding the type. FSRS is the only conformer (`FSRSScheduler`); SM-2 was
/// retired. Pure value semantics — inject `now`/`calendar` for repeatable tests.
protocol Scheduler: Sendable {
    /// The next scheduling state for a card after grading it `grade` at `now`.
    func schedule(current: SchedulingState, grade: Grade, now: Date, calendar: Calendar) -> SchedulingState
}

extension Scheduler {
    /// Convenience overload with the usual defaults.
    func schedule(current: SchedulingState, grade: Grade, now: Date = .now) -> SchedulingState {
        schedule(current: current, grade: grade, now: now, calendar: .current)
    }
}

/// Mutable scheduling state for one card — a pure value type (no SwiftData), so the scheduler is
/// trivially unit-testable. `easeFactor`/`interval`/`repetitions` are legacy SM-2-era fields the card
/// still persists; FSRS seeds its stability/difficulty from them the first time it schedules a card.
struct SchedulingState: Equatable {
    /// Baseline ease for a fresh card, and the point FSRS maps to its default seeded difficulty.
    static let defaultEaseFactor = 2.5

    var easeFactor: Double
    var interval: Int      // days until next review
    var repetitions: Int
    var dueDate: Date
    // FSRS memory state. `stability`/`difficulty` are 0 until FSRS first schedules the card;
    // `lastReviewedAt` is the previous review time FSRS needs to compute elapsed days (populated by the
    // `Card` bridge). All defaulted so simple constructions are unaffected.
    var stability: Double = 0
    var difficulty: Double = 0
    var lastReviewedAt: Date?

    static func initial(now: Date = .now) -> SchedulingState {
        SchedulingState(easeFactor: defaultEaseFactor, interval: 0, repetitions: 0, dueDate: now)
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
