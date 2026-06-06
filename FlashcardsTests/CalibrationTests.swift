import Testing
import Foundation
@testable import Flashcards

@Suite struct CalibrationTests {
    /// A record whose predicted recall is exactly `p` — choose elapsed so 0.9^(elapsed/interval) == p.
    private func record(predicted p: Double, correct: Bool) -> ReviewLog.Record {
        let interval = 10
        let elapsed = Double(interval) * (log(p) / log(0.9))
        return ReviewLog.Record(ts: Date(timeIntervalSince1970: 1_700_000_000), deck: UUID(), card: UUID(),
                                direction: .forward, grade: correct ? 4 : 0, correct: correct,
                                elapsedDays: elapsed, intervalBefore: interval, mature: false)
    }

    @Test func nilBelowMinimumSample() {
        let few = (0..<5).map { _ in record(predicted: 0.9, correct: true) }
        #expect(Calibration.summary(from: few) == nil)
    }

    @Test func newReviewsHaveNoPrediction() {
        let r = ReviewLog.Record(ts: .init(timeIntervalSince1970: 0), deck: UUID(), card: UUID(),
                                 direction: .forward, grade: 4, correct: true, elapsedDays: 0,
                                 intervalBefore: 0, mature: false)
        #expect(Calibration.predicted(r) == nil)
    }

    @Test func wellCalibratedHasNearZeroError() {
        // 30 reviews predicted at 0.8, 80% actually correct ⇒ well-calibrated.
        let records = (0..<30).map { record(predicted: 0.8, correct: $0 % 5 != 0) }   // 24/30 = 0.8
        let s = Calibration.summary(from: records)!
        #expect(abs(s.meanPredicted - 0.8) < 0.01)
        #expect(abs(s.meanActual - 0.8) < 0.01)
        #expect(abs(s.error) < 0.05)
        #expect(Calibration.takeaway(s).contains("well-calibrated"))
    }

    @Test func overconfidenceIsDetected() {
        // Predicted 0.9 but only 60% correct ⇒ schedule overconfident.
        let records = (0..<30).map { record(predicted: 0.9, correct: $0 % 10 < 6) }     // 18/30 = 0.6
        let s = Calibration.summary(from: records)!
        #expect(s.error > 0.1)
        #expect(Calibration.takeaway(s).contains("overconfident"))
        #expect(s.bins.contains { $0.label == "90%+" })   // bucketed by predicted recall
    }
}
