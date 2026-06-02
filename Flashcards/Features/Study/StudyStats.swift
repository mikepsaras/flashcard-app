import Foundation

/// Lightweight daily review log backing the streak + "reviewed today" stats.
///
/// Cards only store their *last* review, so a true multi-day streak can't be derived
/// from them. This keeps a small day-key → review-count map in `UserDefaults` — no
/// model or `.deck` file change — updated once per graded card.
@MainActor
enum StudyStats {
    static let storageKey = "reviewLogByDay"

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func log() -> [String: Int] {
        UserDefaults.standard.dictionary(forKey: storageKey) as? [String: Int] ?? [:]
    }

    /// Records one graded card against today.
    static func recordReview(now: Date = .now) {
        var current = log()
        current[dayKey(now), default: 0] += 1
        UserDefaults.standard.set(current, forKey: storageKey)
    }

    /// Reverses one recorded review for today (used when a grade is undone) so a
    /// grade-then-undo can't inflate "reviewed today" or fabricate a streak.
    static func unrecordReview(now: Date = .now) {
        var current = log()
        let key = dayKey(now)
        guard let count = current[key] else { return }
        if count <= 1 { current.removeValue(forKey: key) } else { current[key] = count - 1 }
        UserDefaults.standard.set(current, forKey: storageKey)
    }

    static func reviewsToday(now: Date = .now) -> Int {
        log()[dayKey(now)] ?? 0
    }

    static func currentStreak(now: Date = .now) -> Int {
        streak(in: log(), asOf: now)
    }

    /// Consecutive days (ending today, or yesterday if today isn't studied yet) that
    /// have at least one review. Pure — the storage-free core, for testing.
    static func streak(in log: [String: Int], asOf now: Date, calendar: Calendar = .current) -> Int {
        let days = Set(log.filter { $0.value > 0 }.keys)
        guard !days.isEmpty else { return 0 }

        var cursor = calendar.startOfDay(for: now)
        // A not-yet-studied today shouldn't zero out an ongoing streak: start counting
        // from yesterday in that case.
        if !days.contains(dayKey(cursor, calendar: calendar)) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: cursor) else { return 0 }
            cursor = yesterday
        }

        var streak = 0
        while days.contains(dayKey(cursor, calendar: calendar)) {
            streak += 1
            guard let prev = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }
}
