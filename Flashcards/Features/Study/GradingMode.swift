import Foundation

/// How the study controls present grading. Chosen per deck (`Deck.gradingMode`).
enum GradingMode: String, CaseIterable, Identifiable {
    case twoButton    // ✕ / ✓  → again / good
    case fourButton   // Again / Hard / Good / Easy

    var id: String { rawValue }

    /// Legacy global key. Grading is now per deck; this remains only so decks saved before
    /// the per-deck setting existed inherit whatever the old global default was, instead of
    /// silently snapping to two-button. See `DeckCodec`.
    static let storageKey = "gradingMode"
    static var legacyDefaultRaw: String {
        UserDefaults.standard.string(forKey: storageKey) ?? twoButton.rawValue
    }

    var title: String {
        switch self {
        case .twoButton:  "Know / Don't know"
        case .fourButton: "Again / Hard / Good / Easy"
        }
    }
}
