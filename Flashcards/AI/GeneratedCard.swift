import Foundation

/// A flashcard suggested by the AI, before it's saved as a SwiftData `Card`.
struct GeneratedCard: Identifiable, Sendable, Equatable {
    let id: UUID
    var term: String
    var definition: String

    init(id: UUID = UUID(), term: String, definition: String) {
        self.id = id
        self.term = term
        self.definition = definition
    }
}
