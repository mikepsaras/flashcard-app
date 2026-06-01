import Foundation

/// Mutable SM-2 state for one card. A pure value type — no SwiftData here, so the
/// algorithm is trivially unit-testable.
struct SchedulingState: Equatable {
    var easeFactor: Double
    var interval: Int      // days until next review
    var repetitions: Int
    var dueDate: Date

    static func initial(now: Date = .now) -> SchedulingState {
        SchedulingState(
            easeFactor: SM2.defaultEaseFactor,
            interval: 0,
            repetitions: 0,
            dueDate: now
        )
    }
}

/// Canonical SuperMemo-2 scheduling (Wozniak). Pure and deterministic — inject
/// `now`/`calendar` for repeatable tests.
enum SM2 {
    static let defaultEaseFactor = 2.5
    static let minimumEaseFactor = 1.3

    static func schedule(
        current: SchedulingState,
        grade: Grade,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> SchedulingState {
        let q = Double(grade.rawValue)
        var ease = current.easeFactor
        var repetitions = current.repetitions
        var interval = current.interval

        if grade.isCorrect {
            switch repetitions {
            case 0:  interval = 1
            case 1:  interval = 6
            default:
                // "Hard" (q=3) advances only modestly (~1.2×) so it's a genuinely
                // shorter step than "Good"/"Easy" (which use the full ease factor),
                // instead of scheduling the identical interval.
                if grade == .hard {
                    interval = max(interval + 1, Int((Double(interval) * 1.2).rounded()))
                } else {
                    interval = Int((Double(interval) * ease).rounded())
                }
            }
            repetitions += 1
        } else {
            repetitions = 0
            interval = 1
        }

        // EF' = EF + (0.1 − (5 − q)(0.08 + (5 − q)·0.02)), floored at 1.3.
        ease += 0.1 - (5 - q) * (0.08 + (5 - q) * 0.02)
        ease = max(ease, minimumEaseFactor)

        let days = max(interval, 1)
        // Snap the due date to the START OF the target day. Without this, a card
        // reviewed at 2pm becomes due "tomorrow at 2pm", so it's missing from the
        // morning's Today queue and every lapse drifts the time later. Start-of-day
        // means it's due first thing and stays due all day.
        let target = calendar.date(byAdding: .day, value: days, to: now) ?? now
        let due = calendar.startOfDay(for: target)

        return SchedulingState(
            easeFactor: ease,
            interval: interval,
            repetitions: repetitions,
            dueDate: due
        )
    }
}
