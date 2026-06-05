import Foundation

/// Centralized `UserDefaults` / `@AppStorage` keys, so each key is spelled once and can't drift
/// between the code that writes it and the code that reads it. (Some keys already live with their
/// feature — `AIProvider.selectedProviderKey`, `StudyStats.storageKey`, `GradingMode.storageKey` —
/// and stay there.)
enum DefaultsKey {
    /// Study: max cards per session (0 = unlimited).
    static let studySessionLimit = "studySessionLimit"
    /// Study: max *new* cards introduced per day across all study (0 = unlimited). Reviews are
    /// never capped by this — only first-time cards. Read via `newCardsPerDayValue` so an unset
    /// key resolves to the default rather than `integer(forKey:)`'s 0 ("unlimited").
    static let newCardsPerDay = "newCardsPerDay"
    /// Default new-cards/day when the user hasn't chosen one — the standard SRS introduction pace.
    static let newCardsPerDayDefault = 20

    /// The effective new-cards-per-day limit, applying the default when the key is unset.
    static func newCardsPerDayValue(_ defaults: UserDefaults = .standard) -> Int {
        defaults.object(forKey: newCardsPerDay) as? Int ?? newCardsPerDayDefault
    }
    /// Library: deck sort order (a `DeckSort` raw value).
    static let deckSort = "deckSort"
    /// Reminders: daily-reminder toggle + time.
    static let remindersEnabled = "remindersEnabled"
    static let reminderHour = "reminderHour"
    static let reminderMinute = "reminderMinute"
    /// Hidden developer mode (unlocked by tapping the version 7×), gating the test-data tools.
    static let developerMode = "developerMode"
    /// Insights: which year the Activity heatmap shows — 0 for the trailing 12 months ("Past year"),
    /// or a calendar year (e.g. 2025). Replaces the old 3M/6M/1Y range key.
    static let heatmapYear = "heatmapYear"
    /// Insights: which Memory-retention graph to show (a `RetentionGraph` raw value).
    static let retentionGraph = "retentionGraph"
    /// Advanced: show the card JSON/CSV import & export affordances (off by default). Opening and
    /// sharing `.cards` deck files stays available regardless of this setting.
    static let showImportExport = "showImportExport"
    /// Developer-only: show projected next-interval subtitles on the study grade buttons. Off by
    /// default so the numbers don't bias honest grading; surfaced in the hidden Developer section.
    static let showGradeIntervals = "showGradeIntervals"
    /// Deck page: the memory-retention ring's look-ahead (a `RetentionHorizon` raw value, in days).
    static let retentionHorizon = "retentionHorizon"
    /// Insights: the hero recall ring's look-ahead (a `RetentionHorizon` raw value; tap to cycle).
    static let insightsRecallHorizon = "insightsRecallHorizon"
    /// Insights: which "Your library" breakdown is shown (a `LibraryGrouping` raw value; tap to cycle).
    static let insightsLibraryGrouping = "insightsLibraryGrouping"
}
