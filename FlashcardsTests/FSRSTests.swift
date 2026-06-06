import Testing
import Foundation
@testable import Flashcards

/// Behavioral tests for the FSRS-4.5 port. They assert the documented *properties* (ordering, growth,
/// graded lapse, bounds, target-retention targeting) rather than brittle exact vectors — exact-value
/// parity with the upstream reference is a pre-ship check before FSRS is wired as a deck default.
@Suite struct FSRSTests {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let cal = Calendar(identifier: .gregorian)

    private func firstReview(_ grade: Grade) -> SchedulingState {
        FSRS.schedule(current: .initial(now: now), grade: grade, now: now, calendar: cal)
    }

    @Test func initialStabilityOrdersByRating() {
        let again = firstReview(.again), hard = firstReview(.hard)
        let good = firstReview(.good), easy = firstReview(.easy)
        #expect(again.stability < hard.stability)
        #expect(hard.stability < good.stability)
        #expect(good.stability < easy.stability)
    }

    @Test func firstReviewProducesValidState() {
        let s = firstReview(.good)
        #expect(s.stability > 0)
        #expect(s.difficulty >= 1 && s.difficulty <= 10)
        #expect(s.interval >= 1)
        #expect(s.dueDate == cal.startOfDay(for: s.dueDate))   // start-of-day snapped, like SM-2
        #expect(s.dueDate > now)
        #expect(s.lastReviewedAt == now)                       // anchor for the next elapsed time
    }

    @Test func intervalApproximatesStabilityAtNinetyPercent() {
        // By construction, FSRS intervals ≈ stability at the default 0.9 target retention.
        let s = firstReview(.good)
        #expect(abs(Double(s.interval) - s.stability) <= 1)
    }

    @Test func repeatedGoodGrowsStabilityAndInterval() {
        var clock = now
        var state = FSRS.schedule(current: .initial(now: clock), grade: .good, now: clock, calendar: cal)
        for _ in 1...4 {
            clock = cal.date(byAdding: .day, value: state.interval, to: clock)!   // review on the due day
            let next = FSRS.schedule(current: state, grade: .good, now: clock, calendar: cal)
            #expect(next.stability > state.stability)   // stability grows with each success
            #expect(next.interval >= state.interval)    // and the interval never shrinks
            state = next
        }
    }

    @Test func lapseDropsStabilityWithoutZeroingIt() {
        // Mature the card with several good reviews, then fail it.
        var clock = now
        var state = FSRS.schedule(current: .initial(now: clock), grade: .good, now: clock, calendar: cal)
        for _ in 0..<5 {
            clock = cal.date(byAdding: .day, value: state.interval, to: clock)!
            state = FSRS.schedule(current: state, grade: .good, now: clock, calendar: cal)
        }
        let matureStability = state.stability
        clock = cal.date(byAdding: .day, value: state.interval, to: clock)!
        let lapsed = FSRS.schedule(current: state, grade: .again, now: clock, calendar: cal)
        #expect(lapsed.stability < matureStability)   // a graded drop…
        #expect(lapsed.stability > 0)                 // …not a reset to ~zero
        #expect(lapsed.repetitions == 0)              // streak resets on a lapse
    }

    @Test func difficultyStaysWithinOneToTen() {
        var clock = now
        var state = FSRS.schedule(current: .initial(now: clock), grade: .again, now: clock, calendar: cal)
        for grade in [Grade.again, .again, .hard, .good] {
            clock = cal.date(byAdding: .day, value: max(state.interval, 1), to: clock)!
            state = FSRS.schedule(current: state, grade: grade, now: clock, calendar: cal)
            #expect(state.difficulty >= 1 && state.difficulty <= 10)
        }
    }

    @Test func schedulerConformerMatchesPureFunction() {
        let a = FSRS.schedule(current: .initial(now: now), grade: .good, now: now, calendar: cal)
        let b = FSRSScheduler().schedule(current: .initial(now: now), grade: .good, now: now, calendar: cal)
        #expect(a == b)
    }

    @Test func seedsFromSM2HistoryNotColdStart() {
        // A card with SM-2 history (interval 30, reviewed 30 days ago, no FSRS state) seeds stability
        // from the interval (S2.5), not the rating's tiny cold-start stability.
        let reviewedAt = cal.date(byAdding: .day, value: -30, to: now)!
        let sm2State = SchedulingState(easeFactor: 2.5, interval: 30, repetitions: 5, dueDate: now,
                                       stability: 0, difficulty: 0, lastReviewedAt: reviewedAt)
        let seeded = FSRS.schedule(current: sm2State, grade: .good, now: now, calendar: cal)
        let coldStart = firstReview(.good)
        #expect(seeded.stability > coldStart.stability * 3)   // clearly seeded from the 30-day interval
        #expect(seeded.interval > coldStart.interval)
    }

    @Test func matchesPyFSRS6ReferenceVectors() {
        // Exact outputs from py-fsrs 6.3.1 (default params, desired_retention 0.9, no learning/
        // relearning steps, fuzzing off), reviewing on each due date: (rating, S, D, interval).
        let seq: [(Grade, Double, Double, Int)] = [
            (.good, 2.306500, 2.118104, 2),
            (.good, 10.964332, 2.111214, 11),
            (.good, 46.280217, 2.104331, 46),
            (.again, 2.932580, 7.389976, 3),
            (.good, 7.778226, 7.377814, 8),
            (.easy, 28.386509, 6.486830, 28),
            (.hard, 51.926443, 7.653023, 52),
        ]
        var clock = Date(timeIntervalSince1970: 1_700_000_000)
        var state = SchedulingState.initial(now: clock)
        for (index, step) in seq.enumerated() {
            state = FSRS.schedule(current: state, grade: step.0, now: clock, calendar: cal)
            #expect(abs(state.stability - step.1) < 0.001, "stability at step \(index)")
            #expect(abs(state.difficulty - step.2) < 0.001, "difficulty at step \(index)")
            #expect(state.interval == step.3, "interval at step \(index)")
            clock = clock.addingTimeInterval(Double(state.interval) * 86_400)   // review on the due date
        }
    }
}
