import Foundation

/// Centralized `UserDefaults` / `@AppStorage` keys, so each key is spelled once and can't drift
/// between the code that writes it and the code that reads it. (Some keys already live with their
/// feature — `AIProvider.selectedProviderKey`, `StudyStats.storageKey`, `GradingMode.storageKey` —
/// and stay there.)
enum DefaultsKey {
    /// Study: max cards per session (0 = unlimited).
    static let studySessionLimit = "studySessionLimit"
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
    /// Insights: whether the optional "By category" / "By section" library breakdowns are expanded.
    static let insightsShowCategories = "insightsShowCategories"
    static let insightsShowSections = "insightsShowSections"
}
