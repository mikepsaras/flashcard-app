import Foundation

/// A 0–5 quality grade (SM-2-derived raw values, kept as the scale FSRS maps from). The study UI emits
/// **Again / Good / Easy** (the 1.8.0 3-button set); `.hard` stays in the enum because the scheduler
/// maps it (FSRS rating 2), but no UI path produces it.
enum Grade: Int, CaseIterable, Identifiable {
    case again = 0   // didn't know it / blackout
    case hard  = 3
    case good  = 4   // knew it
    case easy  = 5

    var id: Int { rawValue }

    /// Known/unknown convenience mapping (used by tests and known-only callers).
    static func from(known: Bool) -> Grade { known ? .good : .again }

    /// A grade of q >= 3 counts as a successful recall.
    var isCorrect: Bool { rawValue >= 3 }
}
