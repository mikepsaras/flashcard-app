import Testing
import Foundation
@testable import Flashcards

@MainActor
@Suite struct StudyStatsTests {
    let cal = Calendar(identifier: .gregorian)
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func key(_ offsetDays: Int) -> String {
        let day = cal.date(byAdding: .day, value: offsetDays, to: now)!
        return StudyStats.dayKey(day, calendar: cal)
    }

    @Test func emptyLogHasNoStreak() {
        #expect(StudyStats.streak(in: [:], asOf: now, calendar: cal) == 0)
    }

    @Test func consecutiveDaysCount() {
        let log = [key(0): 3, key(-1): 1, key(-2): 5]
        #expect(StudyStats.streak(in: log, asOf: now, calendar: cal) == 3)
    }

    @Test func gapBreaksStreak() {
        let log = [key(0): 1, key(-1): 1, key(-3): 1]   // -2 missing
        #expect(StudyStats.streak(in: log, asOf: now, calendar: cal) == 2)
    }

    @Test func notStudiedTodayStillCountsYesterday() {
        let log = [key(-1): 1, key(-2): 1]              // nothing logged today yet
        #expect(StudyStats.streak(in: log, asOf: now, calendar: cal) == 2)
    }

    @Test func zeroCountDaysAreIgnored() {
        let log = [key(0): 0, key(-1): 2]
        #expect(StudyStats.streak(in: log, asOf: now, calendar: cal) == 1)
    }

    // MARK: Storage-backed record / unrecord (UserDefaults round-trip)

    /// Runs `body` with a throwaway UserDefaults suite, cleaned up after — so storage
    /// tests never touch the app's real streak data (the test host shares `.standard`).
    private func withIsolatedDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    @Test func recordThenUnrecordRoundTrips() {
        withIsolatedDefaults { defaults in
            #expect(StudyStats.reviewsToday(now: now, defaults: defaults) == 0)
            StudyStats.recordReview(correct: true, now: now, defaults: defaults)
            StudyStats.recordReview(correct: true, now: now, defaults: defaults)
            #expect(StudyStats.reviewsToday(now: now, defaults: defaults) == 2)
            StudyStats.unrecordReview(correct: true, now: now, defaults: defaults)
            #expect(StudyStats.reviewsToday(now: now, defaults: defaults) == 1)
            StudyStats.unrecordReview(correct: true, now: now, defaults: defaults)
            #expect(StudyStats.reviewsToday(now: now, defaults: defaults) == 0)
        }
    }

    @Test func unrecordOnEmptyStaysAtZero() {
        withIsolatedDefaults { defaults in
            StudyStats.unrecordReview(correct: true, now: now, defaults: defaults)   // nothing recorded yet
            #expect(StudyStats.reviewsToday(now: now, defaults: defaults) == 0)
        }
    }

    @Test func unrecordRemovesDayKeyAtZeroRatherThanLeavingZero() {
        withIsolatedDefaults { defaults in
            StudyStats.recordReview(correct: true, now: now, defaults: defaults)
            StudyStats.unrecordReview(correct: true, now: now, defaults: defaults)
            // A lingering 0-count day would pollute the log; the key must be removed entirely.
            let raw = defaults.dictionary(forKey: StudyStats.storageKey) as? [String: Int] ?? [:]
            #expect(raw.isEmpty)
        }
    }

    @Test func currentStreakReadsFromStorage() {
        withIsolatedDefaults { defaults in
            #expect(StudyStats.currentStreak(now: now, defaults: defaults) == 0)
            StudyStats.recordReview(correct: true, now: now, defaults: defaults)
            #expect(StudyStats.currentStreak(now: now, defaults: defaults) == 1)
        }
    }

    @Test func gradeThenUndoLeavesNoStreakOrCount() {
        // The streak-honesty contract behind StudySessionView.performGrade/performUndo: a
        // recorded review that's fully undone must leave both the daily count and the streak
        // exactly as if it never happened — no fabricated streak.
        withIsolatedDefaults { defaults in
            StudyStats.recordReview(correct: true, now: now, defaults: defaults)
            StudyStats.unrecordReview(correct: true, now: now, defaults: defaults)
            #expect(StudyStats.reviewsToday(now: now, defaults: defaults) == 0)
            #expect(StudyStats.currentStreak(now: now, defaults: defaults) == 0)
        }
    }

    // MARK: Accuracy + longest streak

    @Test func recordTracksCorrectAndIncorrectSeparately() {
        withIsolatedDefaults { defaults in
            StudyStats.recordReview(correct: true, now: now, defaults: defaults)
            StudyStats.recordReview(correct: false, now: now, defaults: defaults)
            StudyStats.recordReview(correct: true, now: now, defaults: defaults)
            let day = StudyStats.dayKey(now)
            #expect(StudyStats.reviewsByDay(defaults: defaults)[day] == 3)
            #expect(StudyStats.correctByDay(defaults: defaults)[day] == 2)
        }
    }

    @Test func unrecordDecrementsCorrectOnlyWhenCorrect() {
        withIsolatedDefaults { defaults in
            StudyStats.recordReview(correct: true, now: now, defaults: defaults)
            StudyStats.recordReview(correct: false, now: now, defaults: defaults)
            let day = StudyStats.dayKey(now)
            StudyStats.unrecordReview(correct: false, now: now, defaults: defaults)  // undo the miss
            #expect(StudyStats.reviewsByDay(defaults: defaults)[day] == 1)
            #expect(StudyStats.correctByDay(defaults: defaults)[day] == 1)
            StudyStats.unrecordReview(correct: true, now: now, defaults: defaults)   // undo the hit
            #expect(StudyStats.reviewsByDay(defaults: defaults)[day] == nil)
            #expect(StudyStats.correctByDay(defaults: defaults)[day] == nil)
        }
    }

    @Test func longestStreakFindsMaxRun() {
        // A 3-day run (0, -1, -2) and a separate 2-day run (-5, -6) ⇒ longest is 3.
        let log = [key(0): 1, key(-1): 1, key(-2): 1, key(-5): 2, key(-6): 1]
        #expect(StudyStats.longestStreak(in: log, calendar: cal) == 3)
    }

    @Test func longestStreakIgnoresZeroDays() {
        let log = [key(0): 0, key(-3): 1]   // a zero day + a lone active day
        #expect(StudyStats.longestStreak(in: log, calendar: cal) == 1)
    }
}
