import Foundation
import SwiftData

/// Codable representation of a deck for `.deck` files. `@Model` types can't be
/// encoded directly, so we map through these DTOs.
///
/// Format v2 adds reverse-direction scheduling + `studyReversed`, plus — added later, the same
/// way grading mode was — optional per-card `section` and the deck's `sectionOrder` +
/// `showSectionsInStudy`. Format v3 adds optional per-card FSRS state (`stability`/`difficulty`,
/// forward + reverse), `tags`, and `extra`. All of these are optional and omitted when empty/default,
/// so files not using them re-encode identically (no phantom edits) — and the version line only
/// advances to 3 when a card actually uses a v3 feature (`encode` stamps 2 otherwise), so existing
/// v2 files stay byte-for-byte unchanged. Manual card order rides in the order of the `cards` array
/// (unsectioned first, then by section), not an explicit field. v1 + v2 files still decode
/// (missing ⇒ defaults).
enum DeckCodec {
    /// The current (max) format version. `encode` stamps a file with the lowest version that can
    /// represent its content — 3 only when a v3 feature is in use — to avoid churning v2 files.
    static let formatVersion = 3

    struct DeckDTO: Codable, Equatable {
        var formatVersion: Int = DeckCodec.formatVersion
        var id: UUID
        var name: String
        var deckDescription: String
        var colorHex: String
        // Optional so `.deck` files written before this field still decode (→ nil).
        var backLabel: String?
        var studyReversed: Bool?
        var gradingMode: String?
        var section: String?
        // v3: card-section names within the deck + whether to show section chips in study.
        var sectionOrder: [String]?
        var showSectionsInStudy: Bool?
        // v3: prompt the learner to type the answer (active recall); omitted when off (the default).
        var typeToAnswer: Bool?
        // Optional deck icon (SF Symbol name or themed preset id); omitted when default.
        var icon: String?
        // v3: scheduling algorithm (a SchedulerKind raw value); omitted when default (SM-2).
        var scheduler: String?
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
        // Optional within-deck section, omitted when empty. (Manual order is the order of the
        // `cards` array — see `encode` — so there's no stored sortOrder.)
        var section: String?
        // Reverse-direction state — optional for v1 backward compatibility.
        var reverseEaseFactor: Double?
        var reverseInterval: Int?
        var reverseRepetitions: Int?
        var reverseDueDate: Date?
        var reverseLastReviewedAt: Date?
        // v3: FSRS state (forward + reverse), topic tags, and answer elaboration — all optional and
        // omitted when default, so v1/v2 files (and cards not using them) re-encode unchanged.
        var stability: Double?
        var difficulty: Double?
        var reverseStability: Double?
        var reverseDifficulty: Double?
        var extra: String?
        var type: String?
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
        // Stamp v3 only when a card actually uses a v3 feature (FSRS state, tags, or extra); otherwise
        // keep v2 so a deck that predates v3 re-encodes byte-identically (the watcher sees no edit).
        let usesV3 = !deck.schedulerRaw.isEmpty || deck.typeToAnswer || deck.cardArray.contains { card in
            card.stability != 0 || card.difficulty != 0 || card.reverseStability != 0
                || card.reverseDifficulty != 0 || !card.extra.isEmpty || !card.typeRaw.isEmpty
        }
        let dto = DeckDTO(
            formatVersion: usesV3 ? 3 : 2,
            id: deck.id,
            name: deck.name,
            deckDescription: deck.deckDescription,
            colorHex: deck.colorHex,
            backLabel: deck.backLabel,
            studyReversed: deck.studyReversed,
            // Omit the key when not explicitly chosen, so files written before this setting
            // re-encode unchanged (the watcher's content comparison sees no phantom edit).
            gradingMode: deck.gradingModeRaw.isEmpty ? nil : deck.gradingModeRaw,
            // Omit when empty so unsectioned decks re-encode identically (no phantom edit),
            // exactly like gradingMode above.
            section: deck.section.isEmpty ? nil : deck.section,
            // Omit when empty/default so decks not using card sections re-encode without noise.
            sectionOrder: deck.sectionOrder.isEmpty ? nil : deck.sectionOrder,
            showSectionsInStudy: deck.showSectionsInStudy ? nil : false,
            // Omit when off (the default) so decks not using type-in re-encode unchanged.
            typeToAnswer: deck.typeToAnswer ? true : nil,
            // Omit when default so decks using the standard icon re-encode without noise.
            icon: deck.icon.isEmpty ? nil : deck.icon,
            // Omit when default (SM-2) so SM-2 decks re-encode unchanged.
            scheduler: deck.schedulerRaw.isEmpty ? nil : deck.schedulerRaw,
            createdAt: deck.createdAt,
            modifiedAt: deck.modifiedAt,
            // Encode in display order — unsectioned first, then each section in `sectionOrder`,
            // and by `sortOrder` within a group — so the file mirrors the on-screen order.
            cards: deck.cardArray
                .sorted { lhs, rhs in
                    (sectionRank(lhs, in: deck), lhs.sortOrder, lhs.createdAt)
                        < (sectionRank(rhs, in: deck), rhs.sortOrder, rhs.createdAt)
                }
                .map(cardDTO)
        )
        return try encoder.encode(dto)
    }

    static func decodeDTO(_ data: Data) throws -> DeckDTO {
        try decoder.decode(DeckDTO.self, from: data)
    }

    /// Builds a `Deck` (with its cards) from a DTO and inserts it into the context.
    @MainActor
    @discardableResult
    static func makeDeck(from dto: DeckDTO, in context: ModelContext) -> Deck {
        let deck = Deck(name: dto.name, deckDescription: dto.deckDescription, colorHex: dto.colorHex)
        deck.id = dto.id
        deck.backLabel = dto.backLabel ?? "Definition"
        deck.studyReversed = dto.studyReversed ?? false
        deck.gradingModeRaw = dto.gradingMode ?? ""
        deck.section = dto.section ?? ""
        deck.sectionOrder = dto.sectionOrder ?? []
        deck.showSectionsInStudy = dto.showSectionsInStudy ?? true
        deck.typeToAnswer = dto.typeToAnswer ?? false
        deck.icon = dto.icon ?? ""
        deck.schedulerRaw = dto.scheduler ?? ""
        deck.createdAt = dto.createdAt
        deck.modifiedAt = dto.modifiedAt
        context.insert(deck)
        for (index, dtoCard) in dto.cards.enumerated() {
            let card = Card(term: dtoCard.term, definition: dtoCard.definition, deck: deck, dueDate: dtoCard.dueDate)
            card.id = dtoCard.id
            apply(dtoCard, to: card, fileOrder: index)
            context.insert(card)
        }
        return deck
    }

    /// Reconciles an existing `Deck` in place to match a DTO (used when an external edit
    /// to the `.deck` file is detected). Mutates scalars and merges cards by id —
    /// updating matches, inserting new, deleting removed — so the deck keeps its
    /// `persistentModelID` (and the user's current selection/editor) intact.
    @MainActor
    static func update(_ deck: Deck, from dto: DeckDTO, in context: ModelContext) {
        deck.name = dto.name
        deck.deckDescription = dto.deckDescription
        deck.colorHex = dto.colorHex
        deck.backLabel = dto.backLabel ?? "Definition"
        deck.studyReversed = dto.studyReversed ?? false
        deck.gradingModeRaw = dto.gradingMode ?? ""
        deck.section = dto.section ?? ""
        deck.sectionOrder = dto.sectionOrder ?? []
        deck.showSectionsInStudy = dto.showSectionsInStudy ?? true
        deck.typeToAnswer = dto.typeToAnswer ?? false
        deck.icon = dto.icon ?? ""
        deck.schedulerRaw = dto.scheduler ?? ""
        deck.createdAt = dto.createdAt
        deck.modifiedAt = dto.modifiedAt

        var existing: [UUID: Card] = [:]
        for card in deck.cardArray { existing[card.id] = card }

        var keep = Set<UUID>()
        for (index, dtoCard) in dto.cards.enumerated() {
            keep.insert(dtoCard.id)
            if let card = existing[dtoCard.id] {
                card.term = dtoCard.term
                card.definition = dtoCard.definition
                apply(dtoCard, to: card, fileOrder: index)
            } else {
                let card = Card(term: dtoCard.term, definition: dtoCard.definition, deck: deck, dueDate: dtoCard.dueDate)
                card.id = dtoCard.id
                apply(dtoCard, to: card, fileOrder: index)
                context.insert(card)
            }
        }
        for card in deck.cardArray where !keep.contains(card.id) {
            context.delete(card)
        }
    }

    // MARK: Field mapping

    /// Sort key for a card's section: unsectioned first (-1), then its index in `sectionOrder`;
    /// an unknown section sorts last. Keeps the encoded file grouped + stable.
    private static func sectionRank(_ card: Card, in deck: Deck) -> Int {
        if card.section.isEmpty { return -1 }
        return deck.sectionOrder.firstIndex(of: card.section) ?? Int.max
    }

    private static func cardDTO(_ card: Card) -> CardDTO {
        CardDTO(
            id: card.id, term: card.term, definition: card.definition,
            createdAt: card.createdAt, modifiedAt: card.modifiedAt,
            easeFactor: card.easeFactor, interval: card.interval,
            repetitions: card.repetitions, dueDate: card.dueDate,
            lastReviewedAt: card.lastReviewedAt,
            // Omit section when empty so unsectioned cards stay noise-free. (Manual order is the
            // array order — see encode() — so there's no separate sortOrder field.)
            section: card.section.isEmpty ? nil : card.section,
            reverseEaseFactor: card.reverseEaseFactor, reverseInterval: card.reverseInterval,
            reverseRepetitions: card.reverseRepetitions, reverseDueDate: card.reverseDueDate,
            reverseLastReviewedAt: card.reverseLastReviewedAt,
            // v3 — omit when default so existing files re-encode identically (no phantom edits).
            stability: card.stability == 0 ? nil : card.stability,
            difficulty: card.difficulty == 0 ? nil : card.difficulty,
            reverseStability: card.reverseStability == 0 ? nil : card.reverseStability,
            reverseDifficulty: card.reverseDifficulty == 0 ? nil : card.reverseDifficulty,
            extra: card.extra.isEmpty ? nil : card.extra,
            type: card.typeRaw.isEmpty ? nil : card.typeRaw
        )
    }

    /// Copies all scheduling + sectioning fields from a DTO onto a card (term/definition handled
    /// by the caller). Missing reverse fields (v1 files) fall back to a fresh schedule. `sortOrder`
    /// comes from the card's position in the file (`fileOrder`) — manual order is the array order,
    /// not a stored field — so existing decks keep their current order.
    private static func apply(_ dto: CardDTO, to card: Card, fileOrder: Int) {
        card.createdAt = dto.createdAt
        card.modifiedAt = dto.modifiedAt
        card.easeFactor = dto.easeFactor
        card.interval = dto.interval
        card.repetitions = dto.repetitions
        card.dueDate = dto.dueDate
        card.lastReviewedAt = dto.lastReviewedAt
        card.section = dto.section ?? ""
        card.sortOrder = fileOrder
        card.reverseEaseFactor = dto.reverseEaseFactor ?? SM2.defaultEaseFactor
        card.reverseInterval = dto.reverseInterval ?? 0
        card.reverseRepetitions = dto.reverseRepetitions ?? 0
        card.reverseDueDate = dto.reverseDueDate ?? dto.createdAt
        card.reverseLastReviewedAt = dto.reverseLastReviewedAt
        // v3 fields — default when absent (v1/v2 files, or cards that don't use them).
        card.stability = dto.stability ?? 0
        card.difficulty = dto.difficulty ?? 0
        card.reverseStability = dto.reverseStability ?? 0
        card.reverseDifficulty = dto.reverseDifficulty ?? 0
        card.extra = dto.extra ?? ""
        card.typeRaw = dto.type ?? ""
    }
}
