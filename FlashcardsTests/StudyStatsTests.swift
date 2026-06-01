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
}
