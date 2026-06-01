import Foundation
import SwiftData

/// Codable representation of a deck for `.deck` files. `@Model` types can't be
/// encoded directly, so we map through these DTOs.
enum DeckCodec {
    static let formatVersion = 1

    struct DeckDTO: Codable, Equatable {
        var formatVersion: Int = DeckCodec.formatVersion
        var id: UUID
        var name: String
        var deckDescription: String
        var colorHex: String
        // Optional so `.deck` files written before this field still decode (→ nil).
        var backLabel: String?
        var createdAt: Date
        var modifiedAt: Date
        var cards: [CardDTO]
    }

    struct CardDTO: Codable, Equatable {
        var id: UUID
        var term: String
        var definition: String
        var createdAt: Date
        var modifiedAt: Date
        var easeFactor: Double
        var interval: Int
        var repetitions: Int
        var dueDate: Date
        var lastReviewedAt: Date?
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    @MainActor
    static func encode(_ deck: Deck) throws -> Data {
        let dto = DeckDTO(
            id: deck.id,
            name: deck.name,
            deckDescription: deck.deckDescription,
            colorHex: deck.colorHex,
            backLabel: deck.backLabel,
            createdAt: deck.createdAt,
            modifiedAt: deck.modifiedAt,
            cards: deck.cardArray
                .sorted { $0.createdAt < $1.createdAt }
                .map { card in
                    CardDTO(
                        id: card.id, term: card.term, definition: card.definition,
                        createdAt: card.createdAt, modifiedAt: card.modifiedAt,
                        easeFactor: card.easeFactor, interval: card.interval,
                        repetitions: card.repetitions, dueDate: card.dueDate,
                        lastReviewedAt: card.lastReviewedAt
                    )
                }
        )
        return try encoder.encode(dto)
    }

    static func decodeDTO(_ data: Data) throws -> DeckDTO {
        try decoder.decode(DeckDTO.self, from: data)
    }

    /// Reconciles an existing `Deck` in place to match a DTO (used when an external
    /// edit to the `.deck` file is detected). Mutates scalars and merges cards by id —
    /// updating matches, inserting new, deleting removed — so the deck keeps its
    /// `persistentModelID` (and the user's current selection/editor) intact.
    @MainActor
    static func update(_ deck: Deck, from dto: DeckDTO, in context: ModelContext) {
        deck.name = dto.name
        deck.deckDescription = dto.deckDescription
        deck.colorHex = dto.colorHex
        deck.backLabel = dto.backLabel ?? "Definition"
        deck.createdAt = dto.createdAt
        deck.modifiedAt = dto.modifiedAt

        var existing: [UUID: Card] = [:]
        for card in deck.cardArray { existing[card.id] = card }

        var keep = Set<UUID>()
        for dtoCard in dto.cards {
            keep.insert(dtoCard.id)
            if let card = existing[dtoCard.id] {
                card.term = dtoCard.term
                card.definition = dtoCard.definition
                card.createdAt = dtoCard.createdAt
                card.modifiedAt = dtoCard.modifiedAt
                card.easeFactor = dtoCard.easeFactor
                card.interval = dtoCard.interval
                card.repetitions = dtoCard.repetitions
                card.dueDate = dtoCard.dueDate
                card.lastReviewedAt = dtoCard.lastReviewedAt
            } else {
                let card = Card(term: dtoCard.term, definition: dtoCard.definition, deck: deck, dueDate: dtoCard.dueDate)
                card.id = dtoCard.id
                card.createdAt = dtoCard.createdAt
                card.modifiedAt = dtoCard.modifiedAt
                card.easeFactor = dtoCard.easeFactor
                card.interval = dtoCard.interval
                card.repetitions = dtoCard.repetitions
                card.lastReviewedAt = dtoCard.lastReviewedAt
                context.insert(card)
            }
        }
        for card in deck.cardArray where !keep.contains(card.id) {
            context.delete(card)
        }
    }

    /// Builds a `Deck` (with its cards) from a DTO and inserts it into the context.
    @MainActor
    @discardableResult
    static func makeDeck(from dto: DeckDTO, in context: ModelContext) -> Deck {
        let deck = Deck(name: dto.name, deckDescription: dto.deckDescription, colorHex: dto.colorHex)
        deck.id = dto.id
        deck.backLabel = dto.backLabel ?? "Definition"
        deck.createdAt = dto.createdAt
        deck.modifiedAt = dto.modifiedAt
        context.insert(deck)
        for dtoCard in dto.cards {
            let card = Card(term: dtoCard.term, definition: dtoCard.definition, deck: deck, dueDate: dtoCard.dueDate)
            card.id = dtoCard.id
            card.createdAt = dtoCard.createdAt
            card.modifiedAt = dtoCard.modifiedAt
            card.easeFactor = dtoCard.easeFactor
            card.interval = dtoCard.interval
            card.repetitions = dtoCard.repetitions
            card.lastReviewedAt = dtoCard.lastReviewedAt
            context.insert(card)
        }
        return deck
    }
}
