import Testing
import Foundation
@testable import Flashcards

@Suite struct SM2Tests {
    // Fixed reference instant + explicit calendar for determinism.
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let cal = Calendar(identifier: .gregorian)

    @Test func firstCorrectReviewGivesIntervalOne() {
        let s = SM2.schedule(current: .initial(now: now), grade: .good, now: now, calendar: cal)
        #expect(s.interval == 1)
        #expect(s.repetitions == 1)
        #expect(s.dueDate == cal.date(byAdding: .day, value: 1, to: now))
    }

    @Test func secondCorrectReviewGivesIntervalSix() {
        var s = SM2.schedule(current: .initial(now: now), grade: .good, now: now, calendar: cal)
        s = SM2.schedule(current: s, grade: .good, now: now, calendar: cal)
        #expect(s.interval == 6)
        #expect(s.repetitions == 2)
    }

    @Test func thirdCorrectReviewMultipliesByEase() {
        var s = SM2.schedule(current: .initial(now: now), grade: .good, now: now, calendar: cal)
        s = SM2.schedule(current: s, grade: .good, now: now, calendar: cal)
        s = SM2.schedule(current: s, grade: .good, now: now, calendar: cal)
        // Three "good" (q=4) grades leave EF unchanged at 2.5, so interval = round(6 × 2.5).
        #expect(s.easeFactor == 2.5)
        #expect(s.interval == 15)
        #expect(s.repetitions == 3)
    }

    @Test func wrongAnswerResetsProgress() {
        var s = SM2.schedule(current: .initial(now: now), grade: .good, now: now, calendar: cal)
        s = SM2.schedule(current: s, grade: .good, now: now, calendar: cal)
        let easeBefore = s.easeFactor
        s = SM2.schedule(current: s, grade: .again, now: now, calendar: cal)
        #expect(s.repetitions == 0)
        #expect(s.interval == 1)
        #expect(s.easeFactor < easeBefore)               // q=0 lowers EF
        #expect(s.easeFactor >= SM2.minimumEaseFactor)
    }

    @Test func easeFactorIsFlooredAtMinimum() {
        var s = SchedulingState.initial(now: now)
        for _ in 0..<20 {
            s = SM2.schedule(current: s, grade: .again, now: now, calendar: cal)
        }
        #expect(s.easeFactor == SM2.minimumEaseFactor)
    }

    @Test func easyGradeRaisesEaseFactor() {
        let s = SM2.schedule(current: .initial(now: now), grade: .easy, now: now, calendar: cal)
        #expect(s.easeFactor > 2.5)                      // q=5 raises EF
        #expect(s.interval == 1)
        #expect(s.repetitions == 1)
    }

    @Test func twoButtonGradeMapping() {
        #expect(Grade.from(known: true) == .good)
        #expect(Grade.from(known: false) == .again)
        #expect(Grade.good.isCorrect)
        #expect(!Grade.again.isCorrect)
    }
}
