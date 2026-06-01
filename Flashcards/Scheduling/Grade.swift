import Foundation

/// A SuperMemo-2 quality grade (0–5). The study UI ships the two-button mapping
/// (✕ → `.again`, ✓ → `.good`); the full four-button set is kept for a future
/// "advanced grading" mode.
enum Grade: Int, CaseIterable, Identifiable {
    case again = 0   // didn't know it / blackout
    case hard  = 3
    case good  = 4   // knew it
    case easy  = 5

    var id: Int { rawValue }

    /// Two-button study mapping.
    static func from(known: Bool) -> Grade { known ? .good : .again }

    /// SM-2 treats q >= 3 as a successful recall.
    var isCorrect: Bool { rawValue >= 3 }
}
