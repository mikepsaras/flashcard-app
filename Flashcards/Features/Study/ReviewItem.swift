import Foundation

/// One unit of study: a card shown in a particular direction. With reverse study
/// enabled a single card yields both a forward and a reverse item, each independently
/// scheduled; the study engine works in terms of these, not bare cards.
struct ReviewItem: Identifiable {
    let card: Card
    let direction: ReviewDirection

    var id: String { "\(card.id.uuidString)-\(direction.rawValue)" }
    var front: String { direction == .forward ? card.term : card.definition }
    var back: String { direction == .forward ? card.definition : card.term }
    var dueDate: Date { card.dueDate(direction) }

    /// Small label shown above the answer side; nil when the deck has labels turned off.
    var backLabel: String? {
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
