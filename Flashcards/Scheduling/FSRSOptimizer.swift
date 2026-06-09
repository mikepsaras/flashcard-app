import Foundation

/// Fits the 21 FSRS weights to a learner's own review history (S2.7), so the scheduler models *their*
/// memory rather than the population average the default weights were trained on. Standard FSRS
/// objective: replay each card's reviews, predict recall R before each, and minimize the binary
/// cross-entropy against the actual outcome — here by Adam with numerical gradients and a light pull
/// toward the defaults (so limited data can't push the weights somewhere degenerate). Pure + tested.
enum FSRSOptimizer {
    /// One review in a unit's history: days since the prior review, the FSRS rating (1…4), and whether
    /// it was recalled (rating ≥ 2).
    struct Review: Equatable, Sendable {
        let elapsedDays: Double
        let rating: Int
        let recalled: Bool
    }

    /// Minimum scored reviews before optimizing is worthwhile — below this it just overfits.
    static let minimumReviews = 100

    /// Groups the review log into per-unit (card + direction) sequences in chronological order. Each
    /// record's stored grade (an SM-2-scale raw value) is mapped to the FSRS 1…4 rating. The first
    /// review of a unit seeds state but isn't scored (no prior recall to predict).
    static func sequences(from records: [ReviewLog.Record]) -> [[Review]] {
        var byUnit: [String: [ReviewLog.Record]] = [:]
        for r in records {
            byUnit["\(r.card.uuidString)-\(r.direction.rawValue)", default: []].append(r)
        }
        return byUnit.values.map { recs in
            recs.sorted { $0.ts < $1.ts }.map { rec in
                let rating = FSRS.fsrsRating(Grade(rawValue: rec.grade) ?? .good)
                // Floor to whole days to match FSRS.schedule, which computes retrievability on INTEGER
                // elapsed days — so the optimizer fits the same R(t) curve the live scheduler applies
                // (avoids a train/serve skew at short intervals where the forgetting curve is steepest).
                return Review(elapsedDays: max(rec.elapsedDays, 0).rounded(.down), rating: rating, recalled: rec.correct)
            }
        }
    }

    /// Reviews that actually contribute to the loss — every non-first review with ≥1 day elapsed (a
    /// same-day re-review has no meaningful forgetting prediction). This is what the optimizer fits.
    static func scoredReviewCount(_ seqs: [[Review]]) -> Int {
        var n = 0
        for seq in seqs { for review in seq.dropFirst() where review.elapsedDays >= 1 { n += 1 } }
        return n
    }

    /// Mean binary cross-entropy of predicted recall vs. outcome over all scored reviews, plus an L2
    /// pull toward `FSRS.defaultWeights` scaled by `reg`. Replays each unit exactly as `FSRS.schedule`
    /// does (new stability from the *prior* difficulty). Lower is better.
    static func loss(_ w: [Double], _ seqs: [[Review]], reg: Double = 0) -> Double {
        let decay = -w[20]
        let factor = pow(0.9, 1.0 / decay) - 1
        var total = 0.0
        var count = 0
        for seq in seqs {
            guard let first = seq.first else { continue }
            var s = FSRS.clampStability(w[first.rating - 1])           // cold start, unscored
            var d = FSRS.clampDifficulty(FSRS.initialDifficulty(first.rating, w))
            for review in seq.dropFirst() {
                let sameDay = review.elapsedDays < 1
                let r = sameDay ? 1.0 : pow(1 + factor * review.elapsedDays / s, decay)
                if !sameDay {
                    let p = min(max(r, 1e-6), 1 - 1e-6)
                    let y = review.recalled ? 1.0 : 0.0
                    total += -(y * log(p) + (1 - y) * log(1 - p))
                    count += 1
                }
                let priorD = d
                d = FSRS.nextDifficulty(priorD, rating: review.rating, w)
                if sameDay {
                    s = FSRS.shortTermStability(s, rating: review.rating, w)
                } else {
                    s = review.rating == 1
                        ? FSRS.forgetStability(difficulty: priorD, stability: s, retrievability: r, w)
                        : FSRS.recallStability(difficulty: priorD, stability: s, retrievability: r, rating: review.rating, w)
                }
            }
        }
        let dataLoss = count > 0 ? total / Double(count) : 0
        guard reg > 0 else { return dataLoss }
        var penalty = 0.0
        for i in 0..<w.count { let diff = w[i] - FSRS.defaultWeights[i]; penalty += diff * diff }
        return dataLoss + reg * penalty
    }

    struct Result: Equatable, Sendable {
        var weights: [Double]
        var lossBefore: Double
        var lossAfter: Double
        var scoredReviews: Int
    }

    /// Minimizes `loss` by Adam with central-difference gradients, from `initial` (the defaults),
    /// clamped to sane FSRS ranges each step. Deterministic given its inputs.
    static func optimize(
        _ seqs: [[Review]],
        initial: [Double] = FSRS.defaultWeights,
        iterations: Int = 120,
        learningRate: Double = 0.03,
        reg: Double = 0.01
    ) -> Result {
        var w = initial
        let n = w.count
        var m = [Double](repeating: 0, count: n)
        var v = [Double](repeating: 0, count: n)
        let beta1 = 0.9, beta2 = 0.999, eps = 1e-8
        let lossBefore = loss(initial, seqs, reg: reg)

        for t in 1...max(iterations, 1) {
            var grad = [Double](repeating: 0, count: n)
            for i in 0..<n {
                let h = max(abs(w[i]) * 1e-3, 1e-5)          // per-weight step: tiny + large weights both move
                var wp = w; wp[i] += h
                var wm = w; wm[i] -= h
                grad[i] = (loss(wp, seqs, reg: reg) - loss(wm, seqs, reg: reg)) / (2 * h)
            }
            for i in 0..<n {
                m[i] = beta1 * m[i] + (1 - beta1) * grad[i]
                v[i] = beta2 * v[i] + (1 - beta2) * grad[i] * grad[i]
                let mHat = m[i] / (1 - pow(beta1, Double(t)))
                let vHat = v[i] / (1 - pow(beta2, Double(t)))
                w[i] -= learningRate * mHat / (sqrt(vHat) + eps)
            }
            w = clamp(w)
        }
        return Result(weights: w, lossBefore: lossBefore,
                      lossAfter: loss(w, seqs, reg: reg), scoredReviews: scoredReviewCount(seqs))
    }

    /// Keeps weights in broad valid ranges so the optimizer can't produce a degenerate scheduler
    /// (negative stability, an out-of-range decay). Looser than py-fsrs's exact bounds, which is fine
    /// alongside the pull-toward-default regularization.
    static func clamp(_ w: [Double]) -> [Double] {
        var c = w
        for i in 0..<c.count { c[i] = max(c[i], 0) }
        for i in 0...3 { c[i] = min(max(c[i], 0.01), 100) }   // initial stabilities
        c[20] = min(max(c[20], 0.1), 0.9)                     // decay
        return c
    }
}
