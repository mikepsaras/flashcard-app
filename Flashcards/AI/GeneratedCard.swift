import Foundation

/// A flashcard suggested by the AI, before it's saved as a SwiftData `Card`.
struct GeneratedCard: Identifiable, Sendable, Equatable {
    let id: UUID
    var term: String
    var definition: String
    /// Optional within-deck section, populated by JSON/CSV import. nil ⇒ unsectioned.
    var section: String?
    /// Optional elaboration ("why"), populated by the AI "Test understanding" intent (B2). Becomes
    /// the saved card's `extra`, shown beneath the answer in study. Empty ⇒ none.
    var extra: String

    init(id: UUID = UUID(), term: String, definition: String, section: String? = nil, extra: String = "") {
        self.id = id
        self.term = term
        self.definition = definition
        self.section = section
        self.extra = extra
    }
}
