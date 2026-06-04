import Foundation

/// Centralized `UserDefaults` / `@AppStorage` keys, so each key is spelled once and can't drift
/// between the code that writes it and the code that reads it. (Some keys already live with their
/// feature — `AIProvider.selectedProviderKey`, `StudyStats.storageKey`, `GradingMode.storageKey` —
/// and stay there.)
enum DefaultsKey {
    /// Study: whether grading advances the spaced-repetition schedule.
    static let trackLearning = "trackLearning"
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
}
