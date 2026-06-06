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
}
