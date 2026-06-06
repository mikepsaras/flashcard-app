import Foundation

/// Free Spaced Repetition Scheduler (FSRS-4.5) — a `Scheduler` conformer that models memory as
/// **stability** (S, days until recall drops to the target) and **difficulty** (D, 1–10) rather than
/// SM-2's single ease factor. Pure + deterministic (inject `now`/`calendar`). Uses the published
/// FSRS-4.5 default weights and a 0.9 target retention.
///
/// ⚠️ Phase 2 scaffold (S2.1): the formulas follow the FSRS-4.5 reference, but the constants/weights
/// should be validated against the upstream implementation (py-fsrs / fsrs4anki) before this is wired
/// as a deck's default scheduler (S2.4/S2.6). Nothing selects it yet — it's landed behind the
/// `Scheduler` seam so it can be exercised in isolation. Per-user weight optimization is S2.7.
enum FSRS {
    /// Published FSRS-4.5 default weights, w0…w16.
    static let defaultWeights: [Double] = [
        0.4, 0.6, 2.4, 5.8, 4.93, 0.94, 0.86, 0.01, 1.49, 0.14, 0.94, 2.18, 0.05, 0.34, 1.26, 0.29, 2.61,
    ]
    /// Target recall probability at the next due date. Will become a user setting; default 0.9 (decision #6).
    static let defaultRequestRetention = 0.9

    // Forgetting curve: R(t) = (1 + FACTOR·t/S)^DECAY, reaching the target at the scheduled interval.
    private static let factor = 19.0 / 81.0
    private static let decay = -0.5
    private static let maxInterval = 36_500   // ~100 years

    static func schedule(
        current: SchedulingState,
        grade: Grade,
        now: Date = .now,
        calendar: Calendar = .current,
        weights w: [Double] = defaultWeights,
        requestRetention rr: Double = defaultRequestRetention
    ) -> SchedulingState {
        let rating = fsrsRating(grade)               // 1…4
        let stability: Double
        let difficulty: Double

        if current.lastReviewedAt == nil {
            // Never reviewed at all — cold start from the rating.
            stability = initStability(rating, w)
            difficulty = initDifficulty(rating, w)
        } else {
            // Reviewed before: use existing FSRS state, or seed it from the card's SM-2 schedule the
            // first time FSRS runs on it (S2.5), so switching a deck to FSRS doesn't discard progress.
            let priorStability = current.stability > 0 ? current.stability : seededStability(interval: current.interval)
            let priorDifficulty = current.stability > 0 ? current.difficulty : seededDifficulty(easeFactor: current.easeFactor)
            let elapsedDays = max(now.timeIntervalSince(current.lastReviewedAt!) / 86_400, 0)
            let r = retrievability(elapsedDays: elapsedDays, stability: priorStability)
            difficulty = nextDifficulty(priorDifficulty, rating: rating, w)
            stability = rating == 1
                ? nextForgetStability(difficulty: difficulty, stability: priorStability, retrievability: r, w)
                : nextRecallStability(difficulty: difficulty, stability: priorStability, retrievability: r, rating: rating, w)
        }

        let interval = nextInterval(stability: stability, rr: rr)
        let target = calendar.date(byAdding: .day, value: interval, to: now) ?? now
        let due = calendar.startOfDay(for: target)   // same start-of-day snapping as SM-2

        return SchedulingState(
            easeFactor: current.easeFactor,           // unused by FSRS; preserved
            interval: interval,
            repetitions: rating == 1 ? 0 : current.repetitions + 1,
            dueDate: due,
            stability: stability,
            difficulty: difficulty,
            lastReviewedAt: now                       // this review becomes the next "elapsed" anchor
        )
    }

    // MARK: FSRS-4.5 formulas

    /// Maps the app's Grade (again/hard/good/easy) to an FSRS rating 1…4.
    static func fsrsRating(_ grade: Grade) -> Int {
        switch grade {
        case .again: 1
        case .hard:  2
        case .good:  3
        case .easy:  4
        }
    }

    static func initStability(_ rating: Int, _ w: [Double]) -> Double {
        max(w[rating - 1], 0.1)
    }

    static func initDifficulty(_ rating: Int, _ w: [Double]) -> Double {
        clampDifficulty(w[4] - exp(w[5] * Double(rating - 1)) + 1)
    }

    /// Probability of recall after `t` days at the given stability.
    static func retrievability(elapsedDays t: Double, stability s: Double) -> Double {
        pow(1 + factor * t / s, decay)
    }

    /// Linear change by rating, then mean reversion toward the easiest initial difficulty.
    static func nextDifficulty(_ d: Double, rating: Int, _ w: [Double]) -> Double {
        let next = d - w[6] * Double(rating - 3)
        let reverted = w[7] * initDifficulty(4, w) + (1 - w[7]) * next
        return clampDifficulty(reverted)
    }

    /// New stability after a successful recall (rating ≥ 2). Grows more for low difficulty, low prior
    /// stability, and lower retrievability (a harder-won success); hard penalty / easy bonus applied.
    static func nextRecallStability(difficulty d: Double, stability s: Double, retrievability r: Double, rating: Int, _ w: [Double]) -> Double {
        let hardPenalty = rating == 2 ? w[15] : 1
        let easyBonus = rating == 4 ? w[16] : 1
        return s * (1 + exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp((1 - r) * w[10]) - 1) * hardPenalty * easyBonus)
    }

    /// New (lower) stability after a lapse (rating == 1) — a graded drop, not a reset to zero.
    static func nextForgetStability(difficulty d: Double, stability s: Double, retrievability r: Double, _ w: [Double]) -> Double {
        w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp((1 - r) * w[14])
    }

    /// Days until recall is predicted to fall to `rr`: t = (S/FACTOR)·(rr^(1/DECAY) − 1). At rr = 0.9
    /// this is ≈ S. Floored at 1 day, capped at `maxInterval`.
    static func nextInterval(stability s: Double, rr: Double) -> Int {
        let raw = (s / factor) * (pow(rr, 1.0 / decay) - 1)
        return min(max(Int(raw.rounded()), 1), maxInterval)
    }

    static func clampDifficulty(_ d: Double) -> Double { min(max(d, 1), 10) }

    // MARK: SM-2 → FSRS seeding (S2.5)

    /// Seed FSRS stability from an SM-2 card's interval the first time FSRS schedules it (interval ≈
    /// stability at the 0.9 target). Floored so a barely-started card still gets a positive value.
    static func seededStability(interval: Int) -> Double { max(Double(interval), 0.5) }

    /// Seed FSRS difficulty from an SM-2 ease factor — lower ease (a harder card) ⇒ higher difficulty.
    /// Approximate; FSRS refines it over the next few reviews. Centered so the default ease maps to ~5.
    static func seededDifficulty(easeFactor ef: Double) -> Double {
        clampDifficulty(5.0 - (ef - SM2.defaultEaseFactor) * 2.0)
    }
}

/// `Scheduler` conformer wrapping `FSRS`, so a deck can select it (S2.4). Carries the weights +
/// target retention it schedules with (defaults today; per-user / per-setting later).
struct FSRSScheduler: Scheduler {
    var weights: [Double] = FSRS.defaultWeights
    var requestRetention: Double = FSRS.defaultRequestRetention

    func schedule(current: SchedulingState, grade: Grade, now: Date, calendar: Calendar) -> SchedulingState {
        FSRS.schedule(current: current, grade: grade, now: now, calendar: calendar,
                      weights: weights, requestRetention: requestRetention)
    }
}
