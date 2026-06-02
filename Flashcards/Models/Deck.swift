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
    /// When true, each card is also studied definition → term, with its own independent
    /// spaced-repetition schedule.
    var studyReversed: Bool = false
    /// Which grading controls this deck uses while studying — 2-button (Know / Don't know)
    /// or 4-button (Again / Hard / Good / Easy), as a `GradingMode` raw value. Empty means
    /// "not explicitly chosen" — a deck saved before this setting existed — and inherits the
    /// legacy default (see `gradingMode`). Decks created in-app always store a concrete value.
    var gradingModeRaw: String = ""
    var createdAt: Date = Date.now
    var modifiedAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Card.deck)
    var cards: [Card]?

    init(
        name: String = "",
        deckDescription: String = "",
        colorHex: String = "#3478F6",
        backLabel: String = "Definition",
        studyReversed: Bool = false,
        gradingMode: GradingMode = .twoButton
    ) {
        self.id = UUID()
        self.name = name
        self.deckDescription = deckDescription
        self.colorHex = colorHex
        self.backLabel = backLabel
        self.studyReversed = studyReversed
        self.gradingModeRaw = gradingMode.rawValue
        self.createdAt = .now
        self.modifiedAt = .now
        self.cards = []
    }
}

extension Deck {
    /// Non-optional view of the cards relationship for convenient use in the UI.
    var cardArray: [Card] { cards ?? [] }
    var cardCount: Int { cardArray.count }

    /// The deck's grading controls (2- or 4-button), backed by `gradingModeRaw`. An empty raw
    /// value (a deck file predating this setting) resolves to the legacy global default, so
    /// existing decks don't silently change.
    var gradingMode: GradingMode {
        get {
            GradingMode(rawValue: gradingModeRaw)
                ?? GradingMode(rawValue: GradingMode.legacyDefaultRaw)
                ?? .twoButton
        }
        set { gradingModeRaw = newValue.rawValue }
    }

    /// Every review unit this deck offers: forward for each card, plus a reverse unit
    /// per card when reverse study is enabled.
    var allReviewItems: [ReviewItem] {
        cardArray.flatMap { card in
            studyReversed
                ? [ReviewItem(card: card, direction: .forward), ReviewItem(card: card, direction: .reverse)]
                : [ReviewItem(card: card, direction: .forward)]
        }
    }

    /// Review units due now (a card can contribute twice when both directions are due).
    var dueReviewItems: [ReviewItem] {
        allReviewItems.filter { $0.card.isDue($0.direction) }
    }

    var dueCount: Int { dueReviewItems.count }
}
