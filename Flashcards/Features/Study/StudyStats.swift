import Foundation

/// Lightweight daily review log backing the streak + "reviewed today" stats.
///
/// Cards only store their *last* review, so a true multi-day streak can't be derived
/// from them. This keeps a small day-key → review-count map in `UserDefaults` — no
/// model or `.deck` file change — updated once per graded card.
@MainActor
enum StudyStats {
    static let storageKey = "reviewLogByDay"
    /// Correct reviews each day, by day-key — a parallel store so accuracy / retention can be
    /// derived without migrating the existing reviews log.
    static let correctStorageKey = "reviewCorrectByDay"
    /// Mature-card reviews each day (interval ≥ the mature threshold *at review time*), plus the
    /// correct subset — two more parallel stores backing Anki-style "true retention" (mature pass
    /// rate). Kept separate so they need no model/file change and start empty (filling as you study).
    static let matureStorageKey = "reviewMatureByDay"
    static let matureCorrectStorageKey = "reviewMatureCorrectByDay"
    /// New cards first studied each day — a parallel store backing the per-day new-card limit
    /// (S0.2), so the queue stops introducing new cards once the day's quota is met (surviving
    /// relaunch). Separate store, no model/file change; starts empty.
    static let newIntroducedStorageKey = "newCardsIntroducedByDay"
    /// Bumped whenever the logs are cleared (reset), so views that read raw UserDefaults rather
    /// than `@AppStorage` re-render. Study sessions already re-render on their own when they end.
    static let revisionKey = "studyStatsRevision"

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func dict(_ key: String, _ defaults: UserDefaults) -> [String: Int] {
        defaults.dictionary(forKey: key) as? [String: Int] ?? [:]
    }

    /// Adds `delta` to `key`'s count for today, removing the day entry at ≤ 0 (so an undone
    /// review never lingers as a 0 or goes negative). Shared by the reviews + correct stores.
    private static func bump(_ key: String, now: Date, by delta: Int, defaults: UserDefaults) {
        var d = dict(key, defaults)
        let day = dayKey(now)
        let value = (d[day] ?? 0) + delta
        if value > 0 { d[day] = value } else { d.removeValue(forKey: day) }
        defaults.set(d, forKey: key)
    }

    /// Records one graded card against today (and, when `correct`, the correct tally too). When
    /// `mature` — the card had already graduated (interval ≥ mature threshold) at review time — it
    /// also feeds the separate mature tallies behind "true retention". `defaults` is injectable so
    /// tests use an isolated suite and never mutate the app's real data (the test host shares
    /// `.standard`).
    static func recordReview(correct: Bool, mature: Bool = false, now: Date = .now, defaults: UserDefaults = .standard) {
        bump(storageKey, now: now, by: 1, defaults: defaults)
        if correct { bump(correctStorageKey, now: now, by: 1, defaults: defaults) }
        if mature {
            bump(matureStorageKey, now: now, by: 1, defaults: defaults)
            if correct { bump(matureCorrectStorageKey, now: now, by: 1, defaults: defaults) }
        }
    }

    /// Reverses one recorded review for today (used when a grade is undone) so a grade-then-undo
    /// can't inflate "reviewed today", accuracy, retention, or the streak. Mirror of `recordReview`
    /// — pass the same `mature` flag the grade was recorded with.
    static func unrecordReview(correct: Bool, mature: Bool = false, now: Date = .now, defaults: UserDefaults = .standard) {
        bump(storageKey, now: now, by: -1, defaults: defaults)
        if correct { bump(correctStorageKey, now: now, by: -1, defaults: defaults) }
        if mature {
            bump(matureStorageKey, now: now, by: -1, defaults: defaults)
            if correct { bump(matureCorrectStorageKey, now: now, by: -1, defaults: defaults) }
        }
    }

    /// Records one *new* card introduced today (its first-ever review), for the per-day new-card
    /// limit. Call alongside `recordReview` only when the graded unit had never been reviewed.
    static func recordNewCardIntroduced(now: Date = .now, defaults: UserDefaults = .standard) {
        bump(newIntroducedStorageKey, now: now, by: 1, defaults: defaults)
    }

    /// Reverses one new-card introduction (used when a first-review grade is undone), mirroring
    /// `unrecordReview` so a grade-then-undo can't permanently consume the day's new-card quota.
    static func unrecordNewCardIntroduced(now: Date = .now, defaults: UserDefaults = .standard) {
        bump(newIntroducedStorageKey, now: now, by: -1, defaults: defaults)
    }

    /// New cards introduced today, for the per-day new-card limit. 0 when none yet.
    static func newCardsIntroducedToday(now: Date = .now, defaults: UserDefaults = .standard) -> Int {
        dict(newIntroducedStorageKey, defaults)[dayKey(now)] ?? 0
    }

    /// Overwrites the day-logs wholesale — used only by the developer test-data tools to seed a
    /// year of synthetic activity. Bumps the revision so live stat views re-read immediately.
    static func overwriteLogs(
        reviews: [String: Int], correct: [String: Int],
        mature: [String: Int], matureCorrect: [String: Int],
        defaults: UserDefaults = .standard
    ) {
        defaults.set(reviews, forKey: storageKey)
        defaults.set(correct, forKey: correctStorageKey)
        defaults.set(mature, forKey: matureStorageKey)
        defaults.set(matureCorrect, forKey: matureCorrectStorageKey)
        defaults.set(defaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }

    /// Clears all recorded study history — streak, reviews, accuracy, and retention.
    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: correctStorageKey)
        defaults.removeObject(forKey: matureStorageKey)
        defaults.removeObject(forKey: matureCorrectStorageKey)
        defaults.removeObject(forKey: newIntroducedStorageKey)
        defaults.set(defaults.integer(forKey: revisionKey) + 1, forKey: revisionKey)
    }

    static func reviewsToday(now: Date = .now, defaults: UserDefaults = .standard) -> Int {
        dict(storageKey, defaults)[dayKey(now)] ?? 0
    }

    /// Full day-key → reviews map (for the heatmap and aggregate totals).
    static func reviewsByDay(defaults: UserDefaults = .standard) -> [String: Int] { dict(storageKey, defaults) }
    /// Full day-key → correct-reviews map (for accuracy / retention).
    static func correctByDay(defaults: UserDefaults = .standard) -> [String: Int] { dict(correctStorageKey, defaults) }
    /// Full day-key → mature-review map and its correct subset (for "true retention").
    static func matureReviewsByDay(defaults: UserDefaults = .standard) -> [String: Int] { dict(matureStorageKey, defaults) }
    static func matureCorrectByDay(defaults: UserDefaults = .standard) -> [String: Int] { dict(matureCorrectStorageKey, defaults) }

    static func currentStreak(now: Date = .now, defaults: UserDefaults = .standard) -> Int {
        streak(in: dict(storageKey, defaults), asOf: now)
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

    /// The longest run of consecutive studied days anywhere in the log (not just ending today).
    /// Pure — the storage-free core, for testing. `calendar` is unused (the keys are Gregorian
    /// "YYYY-MM-DD"); kept for call-site symmetry with `streak`.
    static func longestStreak(in log: [String: Int], calendar: Calendar = .current) -> Int {
        // Convert each studied day-key to an integer day number so consecutive days differ by exactly
        // 1 — far cheaper than parsing every key to a `Date` and doing calendar arithmetic per pair
        // (this runs on every Insights render, over a log that can hold a year+ of days).
        let ordinals = log.compactMap { $0.value > 0 ? dayNumber(fromKey: $0.key) : nil }.sorted()
        guard let first = ordinals.first else { return 0 }
        var longest = 1, run = 1, prev = first
        for ord in ordinals.dropFirst() {
            if ord == prev + 1 { run += 1 } else if ord != prev { run = 1 }
            longest = max(longest, run)
            prev = ord
        }
        return longest
    }

    /// Julian Day Number for a Gregorian "YYYY-MM-DD" day-key (nil if malformed). Pure integer math,
    /// no `Calendar` — used for cheap consecutive-day detection and to place heatmap cells by index.
    static func dayNumber(fromKey key: String) -> Int? {
        let parts = key.split(separator: "-")
        guard parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        let a = (14 - m) / 12
        let yy = y + 4800 - a
        let mm = m + 12 * a - 3
        return d + (153 * mm + 2) / 5 + 365 * yy + yy / 4 - yy / 100 + yy / 400 - 32045
    }
}
