import Foundation

/// Free Spaced Repetition Scheduler (**FSRS-6**) — a `Scheduler` conformer modeling memory as
/// **stability** (S, days) and **difficulty** (D, 1–10) rather than SM-2's single ease factor. Ported
/// from py-fsrs 6.3.1 (MIT) and validated against it to <0.001 on reference vectors (see `FSRSTests`).
///
/// Implements the long-term path plus the same-day (short-term) path. App-level in-session learning
/// steps live in `StudySession` (S0.1), so the scheduler's own learning/relearning steps are unused —
/// equivalent to py-fsrs configured with empty steps. Pure + deterministic (inject `now`/`calendar`).
enum FSRS {
    /// py-fsrs 6.3.1 default parameters, w0…w20 (w20 is the learnable decay).
    static let defaultWeights: [Double] = [
        0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796,
        1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
    ]
    /// Target recall at the next due date (a user setting later). Default 0.9 (decision #6).
    static let defaultRequestRetention = 0.9
    static let stabilityMin = 0.001
    static let maxInterval = 36_500

    static func schedule(
        current: SchedulingState,
        grade: Grade,
        now: Date = .now,
        calendar: Calendar = .current,
        weights w: [Double] = defaultWeights,
        requestRetention rr: Double = defaultRequestRetention
    ) -> SchedulingState {
        let rating = fsrsRating(grade)
        let decay = -w[20]
        let factor = pow(0.9, 1.0 / decay) - 1

        let stability: Double
        let difficulty: Double

        if current.lastReviewedAt == nil {
            // First-ever review — seed S/D from the rating.
            stability = clampStability(w[rating - 1])
            difficulty = clampDifficulty(initialDifficulty(rating, w))
        } else {
            // Existing FSRS state, or seed from the card's SM-2 schedule the first time FSRS runs (S2.5).
            // py-fsrs computes the new stability from the *prior* difficulty, then updates difficulty.
            let priorS = current.stability > 0 ? current.stability : seededStability(interval: current.interval)
            let priorD = current.stability > 0 ? current.difficulty : clampDifficulty(seededDifficulty(easeFactor: current.easeFactor))
            let elapsedDays = max(0, Int(now.timeIntervalSince(current.lastReviewedAt!) / 86_400))   // integer days, like py-fsrs
            difficulty = nextDifficulty(priorD, rating: rating, w)
            if elapsedDays < 1 {
                stability = shortTermStability(priorS, rating: rating, w)
            } else {
                let r = pow(1 + factor * Double(elapsedDays) / priorS, decay)
                stability = rating == 1
                    ? forgetStability(difficulty: priorD, stability: priorS, retrievability: r, w)
                    : recallStability(difficulty: priorD, stability: priorS, retrievability: r, rating: rating, w)
            }
        }

        let interval = nextInterval(stability: stability, decay: decay, factor: factor, rr: rr)
        let due = calendar.startOfDay(for: calendar.date(byAdding: .day, value: interval, to: now) ?? now)

        return SchedulingState(
            easeFactor: current.easeFactor,
            interval: interval,
            repetitions: rating == 1 ? 0 : current.repetitions + 1,
            dueDate: due,
            stability: stability,
            difficulty: difficulty,
            lastReviewedAt: now
        )
    }

    // MARK: FSRS-6 formulas (ported from py-fsrs 6.3.1)

    /// Maps the app's Grade to an FSRS rating 1…4 (Again/Hard/Good/Easy).
    static func fsrsRating(_ grade: Grade) -> Int {
        switch grade {
        case .again: 1
        case .hard:  2
        case .good:  3
        case .easy:  4
        }
    }

    static func initialDifficulty(_ rating: Int, _ w: [Double]) -> Double {
        w[4] - exp(w[5] * Double(rating - 1)) + 1
    }

    /// Days until recall is predicted to fall to `rr`; at rr = 0.9 this is ≈ S. py-fsrs rounds (banker's).
    static func nextInterval(stability: Double, decay: Double, factor: Double, rr: Double) -> Int {
        let raw = (stability / factor) * (pow(rr, 1.0 / decay) - 1)
        return min(max(Int(raw.rounded(.toNearestOrEven)), 1), maxInterval)
    }

    /// Linear-damped change by rating, then mean reversion toward the (unclamped) Easy initial difficulty.
    static func nextDifficulty(_ d: Double, rating: Int, _ w: [Double]) -> Double {
        let target = initialDifficulty(4, w)                       // Easy, unclamped
        let delta = -(w[6] * Double(rating - 3))
        let damped = d + (10.0 - d) * delta / 9.0                  // linear damping
        return clampDifficulty(w[7] * target + (1 - w[7]) * damped)
    }

    /// New stability after a successful recall (rating ≥ 2), using the prior difficulty.
    static func recallStability(difficulty d: Double, stability s: Double, retrievability r: Double, rating: Int, _ w: [Double]) -> Double {
        let hardPenalty = rating == 2 ? w[15] : 1
        let easyBonus = rating == 4 ? w[16] : 1
        return clampStability(s * (1 + exp(w[8]) * (11 - d) * pow(s, -w[9]) * (exp((1 - r) * w[10]) - 1) * hardPenalty * easyBonus))
    }

    /// New (lower) stability after a lapse (rating == 1) — the FSRS-6 long-term value capped by a
    /// short-term ceiling, so a lapse always loses some stability rather than zeroing it.
    static func forgetStability(difficulty d: Double, stability s: Double, retrievability r: Double, _ w: [Double]) -> Double {
        let longTerm = w[11] * pow(d, -w[12]) * (pow(s + 1, w[13]) - 1) * exp((1 - r) * w[14])
        let shortTermCap = s / exp(w[17] * w[18])
        return clampStability(min(longTerm, shortTermCap))
    }

    /// Stability change for a same-day (elapsed < 1 day) review.
    static func shortTermStability(_ s: Double, rating: Int, _ w: [Double]) -> Double {
        var increase = exp(w[17] * (Double(rating - 3) + w[18])) * pow(s, -w[19])
        if rating == 3 || rating == 4 { increase = max(increase, 1.0) }   // Good/Easy never shrink S same-day
        return clampStability(s * increase)
    }

    static func clampStability(_ s: Double) -> Double { max(s, stabilityMin) }
    static func clampDifficulty(_ d: Double) -> Double { min(max(d, 1), 10) }

    // MARK: SM-2 → FSRS seeding (S2.5)

    /// Seed FSRS stability from an SM-2 card's interval the first time FSRS schedules it (interval ≈ S).
    static func seededStability(interval: Int) -> Double { max(Double(interval), 0.5) }
    /// Seed FSRS difficulty from an SM-2 ease factor — lower ease (harder) ⇒ higher difficulty.
    static func seededDifficulty(easeFactor ef: Double) -> Double { 5.0 - (ef - SM2.defaultEaseFactor) * 2.0 }
}

/// `Scheduler` conformer wrapping `FSRS`, selectable per deck (S2.4).
struct FSRSScheduler: Scheduler {
    var weights: [Double] = FSRS.defaultWeights
    var requestRetention: Double = FSRS.defaultRequestRetention

    func schedule(current: SchedulingState, grade: Grade, now: Date, calendar: Calendar) -> SchedulingState {
        FSRS.schedule(current: current, grade: grade, now: now, calendar: calendar,
                      weights: weights, requestRetention: requestRetention)
    }
}
