import Foundation

/// What kind of cards the AI should generate (B2). `recall` drills atomic facts/definitions (the
/// classic flashcard). `understanding` probes *why / how / apply / predict* and attaches a short
/// elaboration to each card, so the answer teaches the reasoning — not just the fact — which is what
/// actually builds transferable expertise. Backed by `@AppStorage` in the generation view.
enum GenerationIntent: String, CaseIterable, Identifiable, Sendable {
    case recall
    case understanding

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recall:        "Key facts"
        case .understanding: "Test understanding"
        }
    }

    var caption: String {
        switch self {
        case .recall:        "Atomic question → answer cards that drill the core facts."
        case .understanding: "Why / how / apply questions, each with a short explanation."
        }
    }
}
