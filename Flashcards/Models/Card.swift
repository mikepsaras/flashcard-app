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

    // MARK: Elaboration
    /// Optional elaboration shown alongside the answer — a worked example, a "why", a source.
    /// Empty ⇒ none. Defaulted ⇒ CloudKit-safe.
    var extra: String = ""
    // MARK: Answer mode (1.8.0) — per-card {flip, type, cloze}
    /// The card's answer mode (an `AnswerMode` raw value). **Empty ⇒ inherit `Deck.defaultAnswerMode`**,
    /// so a deck's flip/type default flows to its cards; a cloze card pins `"cloze"`. Defaulted ⇒
    /// CloudKit-safe.
    var answerModeRaw: String = ""

    // MARK: Card health — leech detection (S7.4)
    /// How many times this card has lapsed (graded **Again** in a real, tracked review). A single
    /// **whole-card** counter — deliberately not per-direction like the schedules above — because a
    /// leech is reformulated as a whole (you rewrite the term/definition pair), and "I keep failing
    /// this" reads the same whichever way the card was asked. Defaulted ⇒ CloudKit-safe.
    var lapses: Int = 0
    /// When true, the card is held out of every study queue (see `Deck.allReviewItems`) — the user's
    /// way to park a leech until they reformulate it, without deleting its history. Defaulted ⇒ CloudKit-safe.
    var suspended: Bool = false

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

    /// Lapse count at or above which a card is treated as a **leech** — one you keep failing, worth
    /// suspending or reformulating (S7.4). The decision-log default is 8.
    static let leechThreshold = 8

    /// A card you keep failing: `lapses` has reached `leechThreshold`. Independent of `suspended` —
    /// a suspended card is still a leech by count; suspension just parks it out of study.
    var isLeech: Bool { lapses >= Card.leechThreshold }

    /// The card's effective answer mode: its own if pinned, otherwise the deck's default (1.8.0).
    func resolvedAnswerMode(deckDefault: AnswerMode) -> AnswerMode {
        AnswerMode(rawValue: answerModeRaw) ?? deckDefault
    }
    /// Whether this is a cloze card. Cloze is pinned on the card (never inherited), so this reads the
    /// raw value directly — no deck needed.
    var isClozeMode: Bool { answerModeRaw == AnswerMode.cloze.rawValue }
}
