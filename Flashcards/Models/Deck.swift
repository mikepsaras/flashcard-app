import Foundation
import SwiftData

/// A named collection of cards.
///
/// CloudKit-safe: scalars defaulted, relationship optional with a declared
/// inverse, delete rule `.cascade` (deleting a deck removes its cards).
@Model
final class Deck {
    var id: UUID = UUID()
    var name: String = ""
    var deckDescription: String = ""
    var colorHex: String = "#3478F6"
    /// Small label shown above the answer side of a card (e.g. "Definition",
    /// "Capital", "Translation"). Customizable per deck.
    var backLabel: String = "Definition"
    var createdAt: Date = Date.now
    var modifiedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card]?

    init(
        name: String = "",
        deckDescription: String = "",
        colorHex: String = "#3478F6",
        backLabel: String = "Definition"
    ) {
        self.id = UUID()
        self.name = name
        self.deckDescription = deckDescription
        self.colorHex = colorHex
        self.backLabel = backLabel
        self.createdAt = .now
        self.modifiedAt = .now
        self.cards = []
    }
}

extension Deck {
    /// Non-optional view of the cards relationship for convenient use in the UI.
    var cardArray: [Card] { cards ?? [] }
    var dueCards: [Card] { cardArray.filter(\.isDue) }
    var dueCount: Int { dueCards.count }
    var cardCount: Int { cardArray.count }
}
