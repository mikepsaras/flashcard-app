import Testing
import Foundation
@testable import Flashcards

/// The per-user FSRS weight optimizer (S2.7): sequence building, the loss, and that Adam reduces it
/// while keeping weights valid.
@Suite struct FSRSOptimizerTests {

    /// A unit's history: a seed review (unscored) then `intervals` later reviews, all recalled `good`.
    private func recalledSeq(intervals: [Double]) -> [FSRSOptimizer.Review] {
        [FSRSOptimizer.Review(elapsedDays: 0, rating: 3, recalled: true)]
            + intervals.map { FSRSOptimizer.Review(elapsedDays: $0, rating: 3, recalled: true) }
    }

    @Test func sequencesGroupByUnitAndOrderByTime() {
        let card = UUID(), deck = UUID()
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        func rec(_ offset: Double, _ grade: Grade, _ correct: Bool) -> ReviewLog.Record {
            ReviewLog.Record(ts: t0.addingTimeInterval(offset * 86_400), deck: deck, card: card, direction: .forward,
                             grade: grade.rawValue, correct: correct, elapsedDays: offset, intervalBefore: 1, mature: false)
        }
        // Deliberately out of chronological order.
        let seqs = FSRSOptimizer.sequences(from: [rec(10, .good, true), rec(0, .good, true), rec(3, .again, false)])
        #expect(seqs.count == 1)
        #expect(seqs[0].map(\.elapsedDays) == [0, 3, 10])          // sorted by ts
        #expect(seqs[0].map(\.rating) == [3, 1, 3])                // grade → FSRS rating
        #expect(seqs[0].map(\.recalled) == [true, false, true])
    }

    @Test func scoredCountSkipsFirstAndSameDayReviews() {
        let seq = [
            FSRSOptimizer.Review(elapsedDays: 0, rating: 3, recalled: true),    // first (seed)
            FSRSOptimizer.Review(elapsedDays: 0.2, rating: 3, recalled: true),  // same-day
            FSRSOptimizer.Review(elapsedDays: 5, rating: 3, recalled: true),    // scored
            FSRSOptimizer.Review(elapsedDays: 10, rating: 1, recalled: false),  // scored
        ]
        #expect(FSRSOptimizer.scoredReviewCount([seq]) == 2)
    }

    @Test func lossIsNonNegativeAndFinite() {
        let seqs = [recalledSeq(intervals: [3, 8, 20])]
        let l = FSRSOptimizer.loss(FSRS.defaultWeights, seqs)
        #expect(l >= 0 && l.isFinite)
    }

    @Test func optimizeReducesLossOnConsistentData() {
        // 60 identical units that are always recalled, even at long intervals — the default weights
        // under-predict that, so fitting should lower the loss.
        let seqs = Array(repeating: recalledSeq(intervals: [3, 8, 20, 45]), count: 60)
        let result = FSRSOptimizer.optimize(seqs, iterations: 60, reg: 0)
        #expect(result.scoredReviews == 60 * 4)
        #expect(result.lossAfter < result.lossBefore)
    }

    @Test func optimizeKeepsWeightsValidAndNeverWorsensLoss() {
        let seqs = Array(repeating: recalledSeq(intervals: [3, 8, 20]), count: 40)
        let r = FSRSOptimizer.optimize(seqs, iterations: 40)
        #expect(r.weights.count == FSRS.defaultWeights.count)
        #expect(r.weights.allSatisfy { $0 >= 0 })
        #expect(r.weights[20] >= 0.1 && r.weights[20] <= 0.9)      // decay clamped
        for i in 0...3 { #expect(r.weights[i] >= 0.01) }           // initial stabilities clamped
        #expect(r.lossAfter <= r.lossBefore + 1e-6)               // gradient descent never increases it
    }

    @Test func weightStoreRoundTrips() {
        let d = UserDefaults(suiteName: "fsrs.test.\(UUID().uuidString)")!
        #expect(!FSRSWeights.isCustomized(d))
        #expect(FSRSWeights.current(d) == FSRS.defaultWeights)

        var custom = FSRS.defaultWeights
        custom[0] = 0.5
        FSRSWeights.set(custom, defaults: d)
        #expect(FSRSWeights.isCustomized(d))
        #expect(FSRSWeights.current(d) == custom)

        FSRSWeights.set([1, 2, 3], defaults: d)                   // wrong length ⇒ cleared
        #expect(!FSRSWeights.isCustomized(d))
        #expect(FSRSWeights.current(d) == FSRS.defaultWeights)
    }
}
