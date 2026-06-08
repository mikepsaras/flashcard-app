import Foundation
import SwiftData

/// Surfaces the cards a learner is weakest on — the "what to study next" read for the Insights
/// dashboard (E7). It replays the review log into Elo ratings and ranks each studied unit by the
/// learner's *expected success* against it (the same quantity behind mastery), so the shakiest cards
/// rise to the top. A measurement/selection layer only — it never touches the spaced schedule.
/// `@MainActor` because resolving a unit's prompt reads `@Model` card text.
struct FocusInsights: Equatable {
    /// One weak unit, with display data resolved from its card.
    struct WeakCard: Identifiable, Equatable {
        var id: String              // Elo unit key (card + direction)
        var prompt: String          // the side you're tested on
        var deckName: String
        var deckColorHex: String
        var deckIcon: String
        var successRate: Double     // expected success 0…1 (lower ⇒ weaker)
        var games: Int
    }

    var weakCards: [WeakCard] = []

    /// Ranks studied units by ascending expected success (weakest first), keeping only those with at
    /// least `Elo.minGamesForDisplay` reviews and a still-existing card. `limit` caps the list.
    @MainActor
    static func make(decks: [Deck], records: [ReviewLog.Record], limit: Int = 6) -> FocusInsights {
        guard !records.isEmpty else { return FocusInsights() }
        let ratings = Elo.replay(records)

        // unit key → its review item + deck, so a rated unit can show its prompt and deck.
        var lookup: [String: (item: ReviewItem, deck: Deck)] = [:]
        for deck in decks {
            for item in deck.allReviewItems {
                lookup[Elo.unitKey(card: item.card.id, direction: item.direction)] = (item, deck)
            }
        }

        var weak: [WeakCard] = []
        for (unit, difficulty) in ratings.difficulty {
            let games = ratings.unitGames[unit] ?? 0
            guard games >= Elo.minGamesForDisplay, let resolved = lookup[unit] else { continue }
            let ability = ratings.ability[Elo.topicKey(deck: resolved.deck.id)] ?? Elo.initialRating
            let success = 1.0 / (1.0 + pow(10.0, (difficulty - ability) / 400.0))
            weak.append(WeakCard(
                id: unit,
                prompt: resolved.item.front,
                deckName: resolved.deck.displayName,
                deckColorHex: resolved.deck.colorHex,
                deckIcon: resolved.deck.icon,
                successRate: success,
                games: games
            ))
        }
        // Weakest first; among ties, more reviews (stronger evidence) ranks higher, then the unit id as a
        // stable final key so the order (and the `prefix` cut) doesn't shift between launches.
        weak.sort { ($0.successRate, -$0.games, $0.id) < ($1.successRate, -$1.games, $1.id) }
        return FocusInsights(weakCards: Array(weak.prefix(limit)))
    }

    /// Review units across the whole library, weakest (highest Elo difficulty) first, for a cross-deck
    /// "practice your weak spots" run. Capped; ordering via `Elo.adaptiveOrder`.
    @MainActor
    static func practiceItems(decks: [Deck], records: [ReviewLog.Record], cap: Int = 40) -> [ReviewItem] {
        let ratings = Elo.replay(records)
        let all = decks.flatMap { $0.allReviewItems }
        return Array(Elo.adaptiveOrder(all, ratings: ratings).prefix(cap))
    }
}
