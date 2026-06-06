import Foundation

/// Calibration of the app's schedule-derived recall *predictions* against what *actually* happened,
/// computed from the review log (E6). For each past review of an already-scheduled card we know the
/// predicted recall at review time — `0.9^(elapsed / interval)` — and the real outcome (correct?).
/// Comparing them answers the honest-mastery question the predicted-recall number can't on its own:
/// *are the predictions real, or just optimism baked into the schedule?* Pure; consumes
/// `ReviewLog.Record`.
enum Calibration {
    /// Minimum scored reviews before a reading is worth showing.
    static let minimumSample = 20
    /// The schedule's assumed recall at the due date (matches `StudyInsights.targetRetentionAtDue`).
    static let target = 0.9

    struct Bin: Equatable, Identifiable {
        var label: String
        var predicted: Double   // mean predicted recall in this bucket (0…1)
        var actual: Double      // measured pass rate in this bucket (0…1)
        var count: Int
        var id: String { label }
    }

    struct Summary: Equatable {
        var sampleCount: Int
        var meanPredicted: Double   // 0…1
        var meanActual: Double      // 0…1
        /// `meanPredicted − meanActual`. Positive ⇒ **over**confident (the schedule predicts more
        /// recall than you actually have, so cards are spaced too far). Negative ⇒ underconfident.
        var error: Double
        var bins: [Bin]
    }

    /// Predicted recall at the moment a review happened. `nil` for first/new reviews (no prior interval).
    static func predicted(_ record: ReviewLog.Record) -> Double? {
        guard record.intervalBefore > 0 else { return nil }
        return min(max(pow(target, record.elapsedDays / Double(record.intervalBefore)), 0), 1)
    }

    /// `nil` until there are at least `minimumSample` scored reviews.
    static func summary(from records: [ReviewLog.Record]) -> Summary? {
        let scored = records.compactMap { record in predicted(record).map { (predicted: $0, correct: record.correct) } }
        guard scored.count >= minimumSample else { return nil }

        let n = Double(scored.count)
        let meanPredicted = scored.reduce(0) { $0 + $1.predicted } / n
        let meanActual = Double(scored.lazy.filter(\.correct).count) / n

        let labels = ["<50%", "50–70%", "70–90%", "90%+"]
        func bucket(_ p: Double) -> Int { p < 0.5 ? 0 : p < 0.7 ? 1 : p < 0.9 ? 2 : 3 }
        var bins: [Bin] = []
        for (index, label) in labels.enumerated() {
            let items = scored.filter { bucket($0.predicted) == index }
            guard !items.isEmpty else { continue }
            let count = Double(items.count)
            bins.append(Bin(
                label: label,
                predicted: items.reduce(0) { $0 + $1.predicted } / count,
                actual: Double(items.filter(\.correct).count) / count,
                count: items.count
            ))
        }

        return Summary(sampleCount: scored.count, meanPredicted: meanPredicted,
                       meanActual: meanActual, error: meanPredicted - meanActual, bins: bins)
    }

    /// A plain-language reading of the calibration error.
    static func takeaway(_ summary: Summary) -> String {
        let predicted = Int((summary.meanPredicted * 100).rounded())
        let actual = Int((summary.meanActual * 100).rounded())
        let gap = Int((abs(summary.error) * 100).rounded())
        let lead = "Predicted recall has averaged \(predicted)%, actual \(actual)% over \(summary.sampleCount) reviews."
        if gap <= 5 {
            return "\(lead) Your predictions are well-calibrated."
        } else if summary.error > 0 {
            return "\(lead) The schedule is overconfident by ~\(gap)% — it expects more recall than you have, so reviews may be spaced too far apart."
        } else {
            return "\(lead) The schedule is underconfident by ~\(gap)% — you recall more than it predicts, so cards could be spaced further."
        }
    }
}
