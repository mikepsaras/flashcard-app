import Foundation

/// A flashcard suggested by the AI, before it's saved as a SwiftData `Card`.
struct GeneratedCard: Identifiable, Sendable, Equatable {
    let id: UUID
    var term: String
    var definition: String
    /// Optional within-deck section, populated by JSON/CSV import. nil ⇒ unsectioned.
    var section: String?

    init(id: UUID = UUID(), term: String, definition: String, section: String? = nil) {
        self.id = id
        self.term = term
        self.definition = definition
        self.section = section
    }
}
