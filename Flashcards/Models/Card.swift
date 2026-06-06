import Foundation
import SwiftData

/// A single flashcard. SM-2 spaced-repetition state is stored inline (strict 1:1
/// with the card, never queried independently).
///
/// CloudKit-safe by construction: every scalar has a default, the relationship is
/// optional, there are no unique constraints.
@Model
final class Card {
    var id: UUID = UUID()
    var term: String = ""
    var definition: String = ""
    var createdAt: Date = Date.now
    var modifiedAt: Date = Date.now

    // MARK: SM-2 scheduling state (forward: term → definition)
    var easeFactor: Double = 2.5     // "EF"; starts at 2.5, never below 1.3
    var interval: Int = 0            // days until the next review
    var repetitions: Int = 0         // consecutive correct reviews (q >= 3)
    var dueDate: Date = Date.now     // <= now ⇒ due
    var lastReviewedAt: Date?        // nil ⇒ never reviewed

    // MARK: Reverse-direction SM-2 state (definition → term)
    // Independent schedule, used only when the deck has reverse study enabled.
    // CloudKit-safe: every scalar defaulted.
    var reverseEaseFactor: Double = 2.5
    var reverseInterval: Int = 0
    var reverseRepetitions: Int = 0
    var reverseDueDate: Date = Date.now
    var reverseLastReviewedAt: Date?

    // MARK: FSRS scheduling state (Phase 1 scaffold; populated once FSRS schedules a card)
    // Memory stability (days) + difficulty, per direction. 0 ⇒ not yet initialized by FSRS; the SM-2
    // scheduler ignores these. CloudKit-safe: every scalar defaulted.
    var stability: Double = 0
    var difficulty: Double = 0
    var reverseStability: Double = 0
    var reverseDifficulty: Double = 0

    // MARK: Sectioning — grouping cards within a deck (Reminders-style)
    /// The card's section within its deck; empty ⇒ the unsectioned area. The deck's set of
    /// section names + their order lives on `Deck.sectionOrder`; cards reference one by name.
    var section: String = ""
    /// Manual position within the card's section (lower = earlier). Defaulted ⇒ CloudKit-safe.
    var sortOrder: Int = 0

    // MARK: Tags + elaboration
    /// Free-form topic tags (cross-deck) — the unit for coverage/mastery and the adaptive practice
    /// mode. Empty ⇒ untagged. Defaulted ⇒ CloudKit-safe.
    var tags: [String] = []
    /// Optional elaboration shown alongside the answer — a worked example, a "why", a source.
    /// Empty ⇒ none. Defaulted ⇒ CloudKit-safe.
    var extra: String = ""

    // Inverse of Deck.cards (optional, per CloudKit rules).
    var deck: Deck?

    init(
        term: String = "",
        definition: String = "",
        deck: Deck? = nil,
        dueDate: Date = .now,
        section: String = "",
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.term = term
        self.definition = definition
        self.createdAt = .now
        self.modifiedAt = .now
        self.easeFactor = 2.5
        self.interval = 0
        self.repetitions = 0
        self.dueDate = dueDate
        self.lastReviewedAt = nil
        self.section = section
        self.sortOrder = sortOrder
        self.deck = deck
    }
}

extension Card {
    /// Reviewed in either direction.
    var hasBeenReviewed: Bool { lastReviewedAt != nil || reverseLastReviewedAt != nil }
}
