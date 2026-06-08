import Foundation

/// One unit of study: a card shown in a particular direction. With reverse study
/// enabled a single card yields both a forward and a reverse item, each independently
/// scheduled; the study engine works in terms of these, not bare cards.
struct ReviewItem: Identifiable {
    let card: Card
    let direction: ReviewDirection

    var id: String { "\(card.id.uuidString)-\(direction.rawValue)" }
    var front: String {
        if card.isClozeMode { return Cloze.front(card.term) }
        return direction == .forward ? card.term : card.definition
    }
    var back: String {
        if card.isClozeMode { return Cloze.back(card.term) }
        return direction == .forward ? card.definition : card.term
    }
    var dueDate: Date { card.dueDate(direction) }

    /// Optional elaboration — a "why", a worked example, a source — shown beneath the answer once
    /// flipped. Empty ⇒ nothing shown. Direction-independent (it's about the card, not the prompt).
    var extra: String { card.extra }

    /// Small label shown above the answer side; nil when the deck has labels turned off.
    var backLabel: String? {
        if card.isClozeMode { return nil }   // the revealed sentence needs no label
        let configured = card.deck?.backLabel ?? "Definition"
        if configured.isEmpty { return nil }
        return direction == .forward ? configured : "Term"
    }

    /// The card's section, shown as a chip on the study card — `nil` when the card's deck has
    /// section chips turned off. Resolved per card so the cross-deck Today queue honors each
    /// deck's own setting.
    var section: String? {
        guard card.deck?.showSectionsInStudy == true else { return nil }
        return card.section.isEmpty ? nil : card.section
    }
}
