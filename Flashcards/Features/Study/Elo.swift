import Foundation

/// Lightweight Elo ratings derived by replaying the review log (E7). Each review is a "match" between
/// the **learner** (per topic — currently per deck) and the **card** (per review unit): a correct
/// answer means the learner beat the card. A card's rating is its *difficulty*; a topic's rating is the
/// learner's *ability*. The gap drives the adaptive practice/cram mode and a surfaced per-topic mastery
/// number. This is a measurement + selection layer — it never touches the spaced schedule (FSRS owns
/// that). Pure; consumes `ReviewLog.Record`.
///
/// v1 uses plain Elo with a games-count gate for display. The Glicko rating-deviation refinement
/// (decision #10) — honest ± uncertainty — is a follow-up.
enum Elo {
    static let initialRating = 1500.0
    static let kFactor = 24.0
    /// Below this many reviews, a topic/card rating is too noisy to show.
    static let minGamesForDisplay = 5

    struct Ratings: Equatable {
        var ability: [String: Double] = [:]      // topic key → learner ability
        var difficulty: [String: Double] = [:]   // unit key → card difficulty
        var topicGames: [String: Int] = [:]
        var unitGames: [String: Int] = [:]
    }

    static func unitKey(card: UUID, direction: ReviewDirection) -> String { "\(card.uuidString)-\(direction.rawValue)" }
    static func topicKey(deck: UUID) -> String { deck.uuidString }

    /// Replays records in chronological order, returning final ability + difficulty ratings. Each match
    /// is zero-sum: the learner's gain equals the card's loss.
    static func replay(_ records: [ReviewLog.Record]) -> Ratings {
        var ratings = Ratings()
        for record in records {
            let topic = topicKey(deck: record.deck)
            let unit = unitKey(card: record.card, direction: record.direction)
            let learner = ratings.ability[topic] ?? initialRating
            let card = ratings.difficulty[unit] ?? initialRating
            let expected = 1.0 / (1.0 + pow(10.0, (card - learner) / 400.0))   // P(learner beats card)
            let delta = kFactor * ((record.correct ? 1.0 : 0.0) - expected)
            ratings.ability[topic] = learner + delta
            ratings.difficulty[unit] = card - delta                            // the card "wins" when you fail
            ratings.topicGames[topic, default: 0] += 1
            ratings.unitGames[unit, default: 0] += 1
        }
        return ratings
    }

    /// Orders review units for adaptive practice/cram: your weakest (highest-difficulty) units first, so
    /// a run drills what you're most likely to miss. Unrated units use the initial rating. Pure.
    static func adaptiveOrder(_ units: [ReviewItem], ratings: Ratings) -> [ReviewItem] {
        units.sorted {
            let lk = unitKey(card: $0.card.id, direction: $0.direction)
            let rk = unitKey(card: $1.card.id, direction: $1.direction)
            let ld = ratings.difficulty[lk] ?? initialRating
            let rd = ratings.difficulty[rk] ?? initialRating
            // Hardest first; break ties on the unit key so the order (and the practice `prefix` cut) is
            // reproducible rather than dependent on the unstable sort over equal difficulties.
            return ld == rd ? lk < rk : ld > rd
        }
    }

    /// A friendly "mastery" reading for one deck: the learner's expected success rate (0…1) over the
    /// cards they've been rated on, plus the games behind it. `nil` until `minGamesForDisplay` reviews.
    /// Pass the records for ONE deck (caller filters) so the replay stays cheap and scoped.
    static func mastery(deckRecords records: [ReviewLog.Record]) -> (rate: Double, games: Int)? {
        guard let deck = records.first?.deck else { return nil }
        let ratings = replay(records)
        let topic = topicKey(deck: deck)
        let games = ratings.topicGames[topic] ?? 0
        guard games >= minGamesForDisplay, !ratings.difficulty.isEmpty else { return nil }
        let ability = ratings.ability[topic] ?? initialRating
        let rate = ratings.difficulty.values
            .map { 1.0 / (1.0 + pow(10.0, ($0 - ability) / 400.0)) }
            .reduce(0, +) / Double(ratings.difficulty.count)
        return (rate, games)
    }
}
